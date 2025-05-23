defmodule Archethic.Mining.PendingTransactionValidation do
  @moduledoc false

  alias Archethic.Contracts

  alias Archethic.Crypto

  alias Archethic.DB

  alias Archethic.Election

  alias Archethic.Governance

  alias Archethic.Networking

  alias Archethic.OracleChain

  alias Archethic.P2P
  alias Archethic.P2P.Message.FirstPublicKey
  alias Archethic.P2P.Message.GetFirstPublicKey
  alias Archethic.P2P.Node

  alias Archethic.Reward

  alias Archethic.SharedSecrets
  alias Archethic.SharedSecrets.NodeRenewal

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Contract
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger

  alias Archethic.Utils

  alias Archethic.Governance.Code.Proposal, as: CodeProposal

  require Logger

  @unit_uco 100_000_000

  @aeweb_schema :archethic
                |> Application.app_dir("priv/json-schemas/aeweb.json")
                |> File.read!()
                |> Jason.decode!()
                |> ExJsonSchema.Schema.resolve()

  @did_schema :archethic
              |> Application.app_dir("priv/json-schemas/did-core.json")
              |> File.read!()
              |> Jason.decode!()
              |> ExJsonSchema.Schema.resolve()

  @token_creation_schema :archethic
                         |> Application.app_dir("priv/json-schemas/token-core.json")
                         |> File.read!()
                         |> Jason.decode!()
                         |> ExJsonSchema.Schema.resolve()

  @token_resupply_schema :archethic
                         |> Application.app_dir("priv/json-schemas/token-resupply.json")
                         |> File.read!()
                         |> Jason.decode!()
                         |> ExJsonSchema.Schema.resolve()

  @tx_max_size Application.compile_env!(:archethic, :transaction_data_content_max_size)

  # @prod? Mix.env() == :prod

  @doc """
  Ensure transaction version is allowed
  Used to differentiate mainnet / testnet network
  """
  @spec(validate_transaction_version(transaction :: Transaction.t()) :: :ok, {:error, String.t()})
  def validate_transaction_version(_tx) do
    :ok
    # if @prod? and System.get_env("ARCHETHIC_NETWORK_TYPE") != "testnet" and version >= 4,
    #   do: {:error, "Transaction V4 are not yet supported on mainnet"},
    #   else: :ok
  end

  @doc """
  Ensure transaction size does not exceed the limit size
  """
  @spec validate_size(transaction :: Transaction.t()) :: :ok | {:error, String.t()}
  def validate_size(%Transaction{data: data, version: tx_version}) do
    tx_size =
      data
      |> TransactionData.serialize(tx_version)
      |> byte_size()

    if tx_size >= @tx_max_size do
      {:error, "Transaction data exceeds limit"}
    else
      :ok
    end
  end

  @doc """
  Ensure the transaction does not already exists
  """
  @spec validate_not_exists(transaction :: Transaction.t()) ::
          :ok | {:error, String.t()}
  def validate_not_exists(%Transaction{address: address}) do
    storage_nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    if TransactionChain.transaction_exists_globally?(address, storage_nodes) do
      {:error, "Transaction already exists"}
    else
      :ok
    end
  end

  @doc """
  Ensure previous public key does not correspond to the current transaction address
  """
  @spec validate_previous_public_key(transaction :: Transaction.t()) :: :ok | {:error, String.t()}
  def validate_previous_public_key(tx = %Transaction{address: address}) do
    if Transaction.previous_address(tx) == address do
      {:error, "Invalid previous public key (should be chain index - 1)"}
    else
      :ok
    end
  end

  @doc """
  Ensure previous signature is valid for the current transaction
  """
  @spec validate_previous_signature(transaction :: Transaction.t()) :: :ok | {:error, String.t()}
  def validate_previous_signature(tx = %Transaction{}) do
    if Transaction.verify_previous_signature?(tx) do
      :ok
    else
      {:error, "Invalid previous signature"}
    end
  end

  @doc """
  Ensure contract is valid (size, code, ownerships)
  """
  @spec validate_contract(transaction :: Transaction.t()) :: :ok | {:error, String.t()}
  def validate_contract(%Transaction{data: %TransactionData{code: "", contract: nil}}), do: :ok

  def validate_contract(%Transaction{version: version, data: %TransactionData{code: code}})
      when code != "" and version >= 4,
      do: {:error, "Invalid transaction, from v4 code is deprecated"}

  def validate_contract(%Transaction{
        version: version,
        data: %TransactionData{contract: %Contract{}}
      })
      when version <= 3,
      do: {:error, "Invalid transaction, before v3 contract is not allowed"}

  def validate_contract(
        tx = %Transaction{
          data: %TransactionData{code: code, contract: contract, ownerships: ownerships}
        }
      ) do
    with :ok <- validate_code_size(code, contract),
         {:ok, contract} <- parse_contract(tx) do
      validate_contract_ownership(contract, ownerships)
    end
  end

  defp validate_code_size(code, _contract) when code != "" do
    if TransactionData.code_size_valid?(code, false),
      do: :ok,
      else: {:error, "Invalid transaction, code exceed max size"}
  end

  defp validate_code_size(_code, %Contract{bytecode: bytecode}) do
    if TransactionData.code_size_valid?(bytecode),
      do: :ok,
      else: {:error, "Invalid transaction, code exceed max size"}
  end

  defp parse_contract(tx) do
    case Contracts.validate_and_parse_transaction(tx) do
      {:ok, contract} -> {:ok, contract}
      {:error, reason} -> {:error, "Smart contract invalid #{inspect(reason)}"}
    end
  end

  defp validate_contract_ownership(contract, ownerships) do
    if Contracts.contains_trigger?(contract),
      do: ensure_ownership_in_contract(ownerships),
      else: :ok
  end

  defp ensure_ownership_in_contract(ownerships) do
    storage_nonce = Crypto.storage_nonce_public_key()

    if Enum.any?(ownerships, &Ownership.authorized_public_key?(&1, storage_nonce)),
      do: :ok,
      else: {:error, "Requires storage nonce public key as authorized public keys"}
  end

  @doc """
  Ensure ownerships are well formated
  """
  @spec validate_ownerships(transaction :: Transaction.t()) :: :ok | {:error, String.t()}
  def validate_ownerships(%Transaction{data: %TransactionData{ownerships: []}}), do: :ok

  def validate_ownerships(%Transaction{data: %TransactionData{ownerships: ownerships}}) do
    Enum.reduce_while(ownerships, :ok, fn ownership, :ok ->
      case Ownership.validate_format(ownership) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          formated_reason = "Ownership: #{Atom.to_string(reason) |> String.replace("_", " ")}"
          {:halt, {:error, formated_reason}}
      end
    end)
  end

  @doc """
  Ensure non fungible token are sent by units
  """
  @spec validate_non_fungible_token_transfer(transaction :: Transaction.t()) ::
          :ok | {:error, String.t()}
  def validate_non_fungible_token_transfer(%Transaction{
        data: %TransactionData{ledger: %Ledger{token: %TokenLedger{transfers: token_transfer}}}
      }) do
    # non fungible token can be sent only by unit
    if Enum.any?(token_transfer, &(&1.token_id != 0 and &1.amount != @unit_uco)),
      do: {:error, "Non fungible token can only be sent by unit"},
      else: :ok
  end

  @doc """
  Ensure transaction respects rules according to it's type
  """
  @spec validate_type_rules(transaction :: Transaction.t(), validation_time :: DateTime.t()) ::
          :ok | {:error, String.t()}
  def validate_type_rules(
        %Transaction{
          type: :transfer,
          data: %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{transfers: uco_transfers},
              token: %TokenLedger{transfers: token_transfers}
            },
            recipients: recipients
          }
        },
        _
      ) do
    if length(uco_transfers) > 0 or length(token_transfers) > 0 or length(recipients) > 0 do
      :ok
    else
      {:error,
       "Transfer's transaction requires some recipients for ledger or smart contract calls"}
    end
  end

  def validate_type_rules(
        %Transaction{
          type: :hosting,
          data: %TransactionData{content: content}
        },
        _
      ) do
    with {:ok, json} <- Jason.decode(content),
         {:schema, :ok} <- {:schema, ExJsonSchema.Validator.validate(@aeweb_schema, json)} do
      :ok
    else
      {:schema, _} ->
        {:error, "Invalid AEWeb transaction - Does not match JSON schema"}

      {:error, _} ->
        {:error, "Invalid AEWeb transaction - Not a JSON format"}
    end
  end

  def validate_type_rules(
        tx = %Transaction{
          type: :node_rewards,
          data: %TransactionData{
            ledger: %Ledger{
              token: %TokenLedger{transfers: token_transfers}
            }
          }
        },
        validation_time
      ) do
    last_scheduling_date = Reward.get_last_scheduling_date(validation_time)

    genesis_address =
      TransactionChain.list_addresses_by_type(:mint_rewards) |> Stream.take(1) |> Enum.at(0)

    {last_reward_address, _} = TransactionChain.get_last_address(genesis_address)

    previous_address = Transaction.previous_address(tx)

    time_validation =
      with {:ok, %Transaction{type: :node_rewards}} <-
             TransactionChain.fetch_transaction(
               previous_address,
               P2P.authorized_and_available_nodes()
             ),
           {^last_reward_address, _} <-
             TransactionChain.get_last_address(genesis_address, last_scheduling_date) do
        :ok
      else
        {:ok, %Transaction{type: :mint_rewards}} ->
          :ok

        _ ->
          {:error, :time}
      end

    with :ok <- time_validation,
         ^token_transfers <- Reward.get_transfers() do
      :ok
    else
      {:error, :time} ->
        Logger.warning("Invalid reward time scheduling",
          transaction_address: Base.encode16(tx.address)
        )

        {:error, "Invalid node rewards trigger time"}

      rewards ->
        Logger.debug("Expected rewards - #{inspect(rewards)}",
          transaction_address: Base.encode16(tx.address),
          transaction_type: :node_rewards
        )

        {:error, "Invalid network pool transfers"}
    end
  end

  def validate_type_rules(
        %Transaction{
          type: :node,
          data: %TransactionData{
            content: content,
            ledger: %Ledger{
              token: %TokenLedger{
                transfers: token_transfers
              }
            }
          },
          previous_public_key: previous_public_key
        },
        _
      ) do
    with :ok <- validate_whitelisted_node(previous_public_key),
         {:ok, ip, port, _http_port, _, _, origin_public_key, key_certificate, mining_public_key} <-
           Node.decode_transaction_content(content),
         {:auth_origin, true} <-
           {:auth_origin,
            Crypto.authorized_key_origin?(origin_public_key, get_allowed_node_key_origins())},
         root_ca_public_key <- Crypto.get_root_ca_public_key(origin_public_key),
         {:auth_cert, true} <-
           {:auth_cert,
            Crypto.verify_key_certificate?(
              origin_public_key,
              key_certificate,
              root_ca_public_key,
              true
            )},
         {:conn, :ok} <-
           {:conn, valid_connection(ip, port, previous_public_key)},
         {:transfers, true} <-
           {:transfers, Enum.all?(token_transfers, &Reward.is_reward_token?(&1.token_address))},
         {:mining_public_key, true} <-
           {:mining_public_key,
            Crypto.valid_public_key?(mining_public_key) and
              Crypto.get_public_key_curve(mining_public_key) == :bls} do
      :ok
    else
      {:error, :node_blacklisted} ->
        {:error, "Invalid node transaction - Node isn't authorized"}

      :error ->
        {:error, "Invalid node transaction's content"}

      {:auth_cert, false} ->
        {:error, "Invalid node transaction with invalid certificate"}

      {:auth_origin, false} ->
        {:error, "Invalid node transaction with invalid key origin"}

      {:conn, {:error, :invalid_ip}} ->
        {:error, "Invalid node's IP address"}

      {:conn, {:error, :existing_node}} ->
        {:error,
         "Invalid node connection (IP/Port) for for the given public key - already existing"}

      {:transfers, false} ->
        {:error, "Invalid transfers, only mining rewards tokens are allowed"}

      {:mining_public_key, false} ->
        {:error, "Invalid mining public key"}
    end
  end

  def validate_type_rules(
        %Transaction{
          type: :origin,
          data: %TransactionData{
            content: content
          }
        },
        _
      ) do
    with {origin_public_key, rest} <-
           Utils.deserialize_public_key(content),
         <<key_certificate_size::16, key_certificate::binary-size(key_certificate_size),
           _::binary>> <- rest,
         {:exists?, false} <-
           {:exists?, SharedSecrets.has_origin_public_key?(origin_public_key)},
         root_ca_public_key <-
           Crypto.get_root_ca_public_key(origin_public_key),
         true <-
           Crypto.verify_key_certificate?(
             origin_public_key,
             key_certificate,
             root_ca_public_key,
             false
           ) do
      :ok
    else
      false ->
        {:error, "Invalid Origin transaction with invalid certificate"}

      {:exists?, true} ->
        {:error, "Invalid Origin transaction Public Key Already Exists"}

      _ ->
        {:error, "Invalid Origin transaction's content"}
    end
  end

  def validate_type_rules(
        %Transaction{
          type: :node_shared_secrets,
          data: %TransactionData{
            content: content,
            ownerships: [%Ownership{secret: secret, authorized_keys: authorized_keys}]
          }
        },
        validation_time
      )
      when is_binary(secret) and byte_size(secret) > 0 and map_size(authorized_keys) > 0 do
    last_scheduling_date = SharedSecrets.get_last_scheduling_date(validation_time)

    genesis_address =
      SharedSecrets.genesis_daily_nonce_public_key()
      |> Crypto.derive_address()

    {last_address, _} = TransactionChain.get_last_address(genesis_address)

    sorted_authorized_keys =
      authorized_keys
      |> Map.keys()
      |> Enum.sort()

    sorted_node_renewal_authorized_keys =
      NodeRenewal.next_authorized_node_public_keys()
      |> Enum.sort()

    with {^last_address, _} <-
           TransactionChain.get_last_address(genesis_address, last_scheduling_date),
         {:ok, _} <- NodeRenewal.decode_transaction_content(content),
         true <- sorted_authorized_keys == sorted_node_renewal_authorized_keys do
      :ok
    else
      :error ->
        {:error, "Invalid node shared secrets transaction content"}

      false ->
        {:error, "Invalid node shared secrets transaction authorized nodes"}

      _address ->
        {:error, "Invalid node shared secrets trigger time"}
    end
  end

  def validate_type_rules(%Transaction{type: :node_shared_secrets}, _) do
    {:error, "Invalid node shared secrets transaction"}
  end

  def validate_type_rules(
        tx = %Transaction{
          type: :code_proposal
        },
        _
      ) do
    with {:ok, prop} <- CodeProposal.from_transaction(tx),
         true <- Governance.valid_code_changes?(prop) do
      :ok
    else
      _ ->
        {:error, "Invalid code proposal"}
    end
  end

  def validate_type_rules(
        tx = %Transaction{
          type: :code_approval,
          data: %TransactionData{
            recipients: [%Recipient{address: proposal_address}]
          }
        },
        _
      ) do
    with {:ok, first_public_key} <- get_first_public_key(tx),
         {:member, true} <-
           {:member, Governance.pool_member?(first_public_key, :technical_council)},
         {:ok, prop} <- Governance.get_code_proposal(proposal_address),
         previous_address <- Transaction.previous_address(tx),
         {:signed, false} <- {:signed, CodeProposal.signed_by?(prop, previous_address)} do
      :ok
    else
      {:member, false} ->
        {:error, "No technical council member"}

      {:error, :not_found} ->
        {:error, "Code proposal doest not exist"}

      {:signed, true} ->
        {:error, "Code proposal already signed"}

      {:error, :network_issue} ->
        {:error, "Network issue"}
    end
  end

  def validate_type_rules(
        %Transaction{
          type: :code_approval,
          data: %TransactionData{
            recipients: []
          }
        },
        _
      ),
      do: {:error, "No recipient specified in code approval"}

  def validate_type_rules(
        %Transaction{
          type: :keychain,
          data: %TransactionData{
            ownerships: ownerships,
            content: content,
            ledger: %Ledger{
              uco: %UCOLedger{transfers: []},
              token: %TokenLedger{transfers: []}
            },
            recipients: []
          }
        },
        _
      )
      when content != "" and ownerships != [] do
    # ownerships validate in :ok <- validate_ownerships(tx),
    with {:ok, json_did} <- Jason.decode(content),
         :ok <- ExJsonSchema.Validator.validate(@did_schema, json_did) do
      :ok
    else
      :error ->
        {:error, "Invalid Keychain transaction"}

      {:error, reason} ->
        Logger.debug("Invalid keychain DID #{inspect(reason)}")
        {:error, "Invalid Keychain transaction"}
    end
  end

  def validate_type_rules(%Transaction{type: :keychain, data: _}, _),
    do: {:error, "Invalid Keychain transaction"}

  def validate_type_rules(
        %Transaction{
          type: :keychain_access,
          previous_public_key: previous_public_key,
          data: %TransactionData{
            content: "",
            ownerships: [ownership = %Ownership{secret: _, authorized_keys: _}],
            ledger: %Ledger{
              uco: %UCOLedger{transfers: []},
              token: %TokenLedger{transfers: []}
            },
            recipients: []
          }
        },
        _
      ) do
    # ownerships validate in :ok <- validate_ownerships(tx),
    # forbid empty ownership or more than one secret, content, uco & token transfers
    if Ownership.authorized_public_key?(ownership, previous_public_key) do
      :ok
    else
      {:error, "Invalid Keychain access transaction - Previous public key must be authorized"}
    end
  end

  def validate_type_rules(%Transaction{type: :keychain_access}, _),
    do: {:error, "Invalid Keychain Access transaction"}

  # Already check by validate_token_transaction function
  def validate_type_rules(%Transaction{type: :token}, _), do: :ok

  # To accept mint_rewards transaction, we ensure that the supply correspond to the
  # burned fees from the last summary and that there is no transaction since the last
  # reward schedule
  def validate_type_rules(
        %Transaction{type: :mint_rewards, data: %TransactionData{content: content}},
        _
      ) do
    total_fee = DB.get_latest_burned_fees()

    genesis_address =
      TransactionChain.list_addresses_by_type(:mint_rewards) |> Stream.take(1) |> Enum.at(0)

    {last_address, _} = TransactionChain.get_last_address(genesis_address)

    with {:ok, %{"supply" => ^total_fee}} <- Jason.decode(content),
         {^last_address, _} <-
           TransactionChain.get_last_address(genesis_address, Reward.get_last_scheduling_date()) do
      :ok
    else
      {:ok, %{"supply" => _}} -> {:error, "The supply do not match burned fees from last summary"}
      {_, _} -> {:error, "There is already a mint rewards transaction since last schedule"}
      e -> e
    end
  end

  def validate_type_rules(
        %Transaction{
          type: :oracle,
          data: %TransactionData{
            content: content
          }
        },
        validation_time
      ) do
    last_scheduling_date = OracleChain.get_last_scheduling_date(validation_time)

    genesis_address =
      validation_time
      |> OracleChain.next_summary_date()
      |> Crypto.derive_oracle_address(0)

    {last_address, _} = TransactionChain.get_last_address(genesis_address)

    with {^last_address, _} <-
           TransactionChain.get_last_address(genesis_address, last_scheduling_date),
         true <- OracleChain.valid_services_content?(content) do
      :ok
    else
      {_, _} ->
        {:error, "Invalid oracle trigger time"}

      false ->
        {:error, "Invalid oracle transaction"}
    end
  end

  def validate_type_rules(
        %Transaction{
          type: :oracle_summary,
          data: %TransactionData{
            content: content
          },
          previous_public_key: previous_public_key
        },
        validation_time
      ) do
    previous_address = Crypto.derive_address(previous_public_key)

    last_scheduling_date = OracleChain.get_last_scheduling_date(validation_time)

    genesis_address =
      validation_time
      |> OracleChain.next_summary_date()
      |> Crypto.derive_oracle_address(0)

    {last_address, _} = TransactionChain.get_last_address(genesis_address)

    transactions =
      TransactionChain.get(previous_address, data: [:content], validation_stamp: [:timestamp])

    with {^last_address, _} <-
           TransactionChain.get_last_address(genesis_address, last_scheduling_date),
         eq when eq in [:gt, :eq] <-
           DateTime.compare(validation_time, OracleChain.previous_summary_date(validation_time)),
         true <- OracleChain.valid_summary?(content, transactions) do
      :ok
    else
      {_, _} ->
        {:error, "Invalid oracle summary trigger time"}

      :lt ->
        {:error, "Invalid oracle summary trigger time"}

      false ->
        {:error, "Invalid oracle summary transaction"}
    end
  end

  def validate_type_rules(
        %Transaction{type: :contract, data: %TransactionData{code: code, contract: contract}},
        _
      )
      when code == "" and contract == nil,
      do: {:error, "Invalid contract type transaction -  contract's code is empty"}

  def validate_type_rules(
        %Transaction{type: :data, data: %TransactionData{content: "", ownerships: []}},
        _
      ),
      do: {:error, "Invalid data type transaction - Both content & ownership are empty"}

  def validate_type_rules(_, _), do: :ok

  defp validate_whitelisted_node(public_key) do
    first_public_key = TransactionChain.get_first_public_key(public_key)

    blacklisted? =
      File.read!(Application.app_dir(:archethic, "priv/blacklist.txt"))
      |> String.split("\n", trim: true)
      |> Enum.any?(&(Base.encode16(first_public_key) == &1))

    if blacklisted?,
      do: {:error, :node_blacklisted},
      else: :ok
  end

  @doc """
  Ensure network transactions are in the expected chain
  """
  @spec validate_network_chain(transaction :: Transaction.t()) ::
          :ok | {:error, String.t()}
  def validate_network_chain(tx) do
    case Transaction.network_type?(tx.type) do
      false ->
        # not a network tx, no need to validate with last tx
        :ok

      true ->
        # when network tx, check with previous transaction
        if valid_network_chain?(tx.type, tx),
          do: :ok,
          else: {:error, "Invalid Transaction Type"}
    end
  end

  defp valid_network_chain?(type, tx = %Transaction{})
       when type in [:oracle, :oracle_summary] do
    with local_gen_addr when local_gen_addr != nil <- OracleChain.genesis_addresses(),
         {:ok, chain_gen_addr} <- fetch_previous_tx_genesis_address(tx) do
      local_gen_addr.current |> elem(0) == chain_gen_addr ||
        local_gen_addr.prev |> elem(0) == chain_gen_addr
    else
      _ -> false
    end
  end

  defp valid_network_chain?(type, tx = %Transaction{})
       when type in [:mint_rewards, :node_rewards] do
    with local_gen_addr when local_gen_addr != nil <- Reward.genesis_address(),
         {:ok, chain_gen_addr} <- fetch_previous_tx_genesis_address(tx) do
      local_gen_addr == chain_gen_addr
    else
      _ -> false
    end
  end

  defp valid_network_chain?(:node_shared_secrets, tx = %Transaction{}) do
    with local_gen_addr when local_gen_addr != nil <-
           SharedSecrets.genesis_address(:node_shared_secrets),
         {:ok, chain_gen_addr} <- fetch_previous_tx_genesis_address(tx) do
      local_gen_addr == chain_gen_addr
    else
      _ -> false
    end
  end

  defp valid_network_chain?(:origin, tx = %Transaction{}) do
    with local_gen_addr when local_gen_addr != nil <-
           SharedSecrets.genesis_address(:origin),
         {:ok, chain_gen_addr} <- fetch_previous_tx_genesis_address(tx) do
      chain_gen_addr in local_gen_addr
    else
      _ -> false
    end
  end

  defp valid_network_chain?(_type, _tx), do: true

  defp fetch_previous_tx_genesis_address(tx) do
    tx
    |> Transaction.previous_address()
    |> TransactionChain.fetch_genesis_address(P2P.authorized_and_available_nodes())
  end

  @doc """
  Ensure token transaction is valid and returns token decimals
  """
  @spec validate_token_transaction(transaction :: Transaction.t()) :: :ok | {:error, String.t()}
  def validate_token_transaction(
        tx = %Transaction{type: type, data: %TransactionData{content: content}}
      )
      when type in [:token, :mint_rewards] do
    with {:ok, json_token} <- Jason.decode(content),
         :ok <- verify_token_creation(tx, json_token) do
      verify_token_recipients(json_token)
      :ok
    else
      {:error, %Jason.DecodeError{}} -> {:error, "Invalid token transaction - invalid JSON"}
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_token_transaction(_), do: :ok

  defp verify_token_creation(tx, json_token) do
    cond do
      ExJsonSchema.Validator.valid?(@token_creation_schema, json_token) ->
        verify_token_creation(json_token)

      ExJsonSchema.Validator.valid?(@token_resupply_schema, json_token) ->
        verify_token_resupply(tx, json_token)

      true ->
        {:error, "Invalid token transaction - neither a token creation nor a token resupply"}
    end
  end

  defp verify_token_creation(json_token) do
    with %{
           "type" => "non-fungible",
           "supply" => supply,
           "collection" => collection
         } <- json_token,
         {:decimals, 8} <- {:decimals, Map.get(json_token, "decimals", 8)},
         {:length, ^supply} <- {:length, length(collection) * @unit_uco},
         {:id, true} <- {:id, valid_collection_id?(collection)} do
      :ok
    else
      %{"type" => "fungible", "collection" => _collection} ->
        {:error, "Invalid token transaction - Fungible should not have collection attribute"}

      %{"type" => "fungible"} ->
        :ok

      %{"type" => "non-fungible", "supply" => supply} when supply != @unit_uco ->
        {:error,
         "Invalid token transaction - Non fungible should have collection attribute or supply should be #{@unit_uco}"}

      %{"type" => "non-fungible"} ->
        :ok

      {:decimals, _} ->
        {:error, "Invalid token transaction - Non fungible should have 8 decimals"}

      {:length, _} ->
        {:error,
         "Invalid token transaction - Supply should match collection for non-fungible tokens"}

      {:id, false} ->
        {:error,
         "Invalid token transaction - Specified id must be different for all item in the collection"}
    end
  end

  defp verify_token_resupply(tx, %{"token_reference" => token_ref}) do
    # strict because there was a json schema validation before
    token_address = Base.decode16!(token_ref, case: :mixed)

    storage_nodes =
      Election.chain_storage_nodes(token_address, P2P.authorized_and_available_nodes())

    # fetch in parallel the data we need
    tasks = [
      Task.Supervisor.async_nolink(Archethic.task_supervisors(), fn ->
        fetch_previous_tx_genesis_address(tx)
      end),
      Task.Supervisor.async_nolink(Archethic.task_supervisors(), fn ->
        TransactionChain.fetch_genesis_address(token_address, storage_nodes)
      end),
      Task.Supervisor.async_nolink(Archethic.task_supervisors(), fn ->
        TransactionChain.fetch_transaction(token_address, storage_nodes)
      end)
    ]

    # Shut down the tasks that did not reply nor exit
    [tx_genesis_result, ref_genesis_result, ref_tx_result] =
      Task.yield_many(tasks)
      |> Enum.map(fn {task, res} ->
        res || Task.shutdown(task, :brutal_kill)
      end)

    with {:ok, {:ok, genesis_address}} <- tx_genesis_result,
         {:ok, {:ok, ^genesis_address}} <- ref_genesis_result,
         {:ok, {:ok, %Transaction{data: %TransactionData{content: content}}}} <- ref_tx_result,
         {:ok, reference_json_token} <- Jason.decode(content),
         %{"type" => "fungible", "allow_mint" => true} <- reference_json_token do
      :ok
    else
      nil ->
        {:error, "Timeout when fetching the reference token or the genesis address"}

      {:exit, _} ->
        {:error, "Error when fetching the reference token or the genesis address"}

      %{"type" => "non-fungible"} ->
        {:error, "Invalid token transaction - token_reference must be fungible"}

      %{"type" => "fungible"} ->
        {:error, "Invalid token transaction - token_reference does not have allow_mint: true"}

      {:ok, {:ok, _}} ->
        {:error,
         "Invalid token transaction - token_reference is not in the same transaction chain"}

      {:ok, {:error, :transaction_not_exists}} ->
        {:error, "Invalid token transaction - token_reference not found"}

      {:ok, {:error, :network_issue}} ->
        {:error, "A network issue was raised, please retry later"}

      {:error, %Jason.DecodeError{}} ->
        {:error,
         "Invalid token transaction - token_reference exists but does not contain a valid JSON"}
    end
  end

  defp verify_token_recipients(json_token = %{"recipients" => recipients, "supply" => supply})
       when is_list(recipients) do
    # resupply token transactions do not have a type, but is applied only to fungible tokens
    fungible? = Map.get(json_token, "type", "fungible") == "fungible"

    %{res: res} =
      Enum.reduce_while(
        recipients,
        %{sum: 0, token_ids: MapSet.new(), res: :ok},
        fn recipient = %{"amount" => amount}, acc = %{sum: sum, token_ids: token_ids} ->
          with :ok <- validate_token_recipient_amount(amount, fungible?),
               :ok <- validate_token_recipient_total(amount, sum, supply),
               :ok <- validate_token_recipient_token_id(recipient, fungible?, token_ids) do
            token_id = Map.get(recipient, "token_id", 0)

            new_acc =
              acc
              |> Map.update!(:sum, &(&1 + amount))
              |> Map.update!(:token_ids, &MapSet.put(&1, token_id))

            {:cont, new_acc}
          else
            error -> {:halt, Map.put(acc, :res, error)}
          end
        end
      )

    res
  end

  defp verify_token_recipients(_), do: :ok

  defp validate_token_recipient_amount(_, true), do: :ok
  defp validate_token_recipient_amount(amount, false) when amount == @unit_uco, do: :ok

  defp validate_token_recipient_amount(_, false),
    do: {:error, "Invalid token transaction - invalid amount in recipients"}

  defp validate_token_recipient_total(amount, sum, supply) when sum + amount <= supply, do: :ok

  defp validate_token_recipient_total(_, _, _),
    do: {:error, "Invalid token transaction - sum of recipients' amounts is bigger than supply"}

  defp validate_token_recipient_token_id(%{"token_id" => _}, true, _),
    do:
      {:error,
       "Invalid token transaction - recipient with token_id is now allowed on fungible token"}

  defp validate_token_recipient_token_id(_recipient, true, _), do: :ok

  defp validate_token_recipient_token_id(%{"token_id" => token_id}, false, token_ids) do
    if MapSet.member?(token_ids, token_id) do
      {:error,
       "Invalid token transaction - recipient must have unique token_id for non fungible token"}
    else
      :ok
    end
  end

  defp validate_token_recipient_token_id(_, false, _),
    do:
      {:error, "Invalid token transaction - recipient must have token_id for non fungible token"}

  defp valid_collection_id?(collection) do
    # If an id is specified in an item of the collection,
    # all items must have a different specified id
    if Enum.at(collection, 0) |> Map.has_key?("id") do
      Enum.reduce_while(collection, MapSet.new(), fn properties, acc ->
        id = Map.get(properties, "id")

        if id != nil && !MapSet.member?(acc, id) do
          {:cont, MapSet.put(acc, id)}
        else
          {:halt, MapSet.new()}
        end
      end)
      |> MapSet.size() > 0
    else
      Enum.all?(collection, &(!Map.has_key?(&1, "id")))
    end
  end

  defp get_allowed_node_key_origins do
    :archethic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:allowed_node_key_origins, [])
  end

  defp get_first_public_key(tx = %Transaction{}) do
    previous_address = Transaction.previous_address(tx)

    previous_address
    |> Election.chain_storage_nodes(P2P.authorized_and_available_nodes())
    |> P2P.sort_by_nearest_nodes()
    |> Enum.filter(&P2P.node_connected?/1)
    |> get_first_public_key(previous_address)
  end

  defp get_first_public_key([node | rest], public_key) do
    case P2P.send_message(node, %GetFirstPublicKey{public_key: public_key}) do
      {:ok, %FirstPublicKey{public_key: public_key}} ->
        {:ok, public_key}

      {:error, _} ->
        get_first_public_key(rest, public_key)
    end
  end

  defp get_first_public_key([], _), do: {:error, :network_issue}

  defp valid_connection(ip, port, previous_public_key) do
    with :ok <- Networking.validate_ip(ip),
         false <- P2P.duplicating_node?(ip, port, previous_public_key) do
      :ok
    else
      true ->
        {:error, :existing_node}

      {:error, :invalid_ip} ->
        {:error, :invalid_ip}
    end
  end
end
