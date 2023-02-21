defmodule Archethic.Mining.PendingTransactionValidation do
  @moduledoc false

  alias Archethic.{
    Contracts,
    Contracts.Contract,
    Crypto,
    DB,
    SharedSecrets,
    Election,
    Governance,
    Networking,
    OracleChain,
    P2P,
    P2P.Message.FirstPublicKey,
    P2P.Message.GetFirstPublicKey,
    P2P.Message.GetTransactionSummary,
    P2P.Message.TransactionSummaryMessage,
    P2P.Message.NotFound,
    P2P.Node,
    Reward,
    SharedSecrets.NodeRenewal,
    Utils,
    TransactionChain
  }

  alias Archethic.TransactionChain.{
    Transaction,
    TransactionData,
    TransactionData.Ledger,
    TransactionData.Ownership,
    TransactionData.UCOLedger,
    TransactionData.TokenLedger,
    TransactionSummary
  }

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

  @token_schema :archethic
                |> Application.app_dir("priv/json-schemas/token-core.json")
                |> File.read!()
                |> Jason.decode!()
                |> ExJsonSchema.Schema.resolve()

  @code_max_size Application.compile_env!(:archethic, :transaction_data_code_max_size)

  @tx_max_size Application.compile_env!(:archethic, :transaction_data_content_max_size)

  @doc """
  Determines if the transaction is accepted into the network
  """
  @spec validate(Transaction.t(), DateTime.t()) :: :ok | {:error, any()}
  def validate(
        tx = %Transaction{address: address, type: type},
        validation_time = %DateTime{} \\ DateTime.utc_now()
      ) do
    start = System.monotonic_time()

    with :ok <- validate_size(tx),
         :ok <- valid_not_exists(tx),
         :ok <- valid_previous_signature(tx),
         :ok <- validate_contract(tx),
         :ok <- validate_ownerships(tx),
         :ok <- do_accept_transaction(tx, validation_time),
         :ok <- validate_previous_transaction_type?(tx) do
      :telemetry.execute(
        [:archethic, :mining, :pending_transaction_validation],
        %{duration: System.monotonic_time() - start},
        %{transaction_type: type}
      )

      :ok
    else
      {:error, reason} = e ->
        Logger.info("Invalid Transaction: #{reason}",
          transaction_address: Base.encode16(address),
          transaction_type: type
        )

        e
    end
  end

  defp validate_size(%Transaction{data: data, version: tx_version}) do
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

  defp valid_not_exists(%Transaction{address: address}) do
    storage_nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    conflict_resolver = fn results ->
      # Prioritize transactions results over not found
      case Enum.filter(results, &match?(%TransactionSummaryMessage{}, &1)) do
        [] ->
          %NotFound{}

        res ->
          Enum.sort_by(res, & &1.timestamp, {:desc, DateTime})
          |> List.first()
      end
    end

    case P2P.quorum_read(
           storage_nodes,
           %GetTransactionSummary{address: address},
           conflict_resolver
         ) do
      {:ok,
       %TransactionSummaryMessage{transaction_summary: %TransactionSummary{address: ^address}}} ->
        {:error, "Transaction already exists"}

      {:ok, %NotFound{}} ->
        :ok

      {:error, _} = e ->
        e
    end
  end

  @spec valid_previous_signature(tx :: Transaction.t()) :: :ok | {:error, any()}
  defp valid_previous_signature(tx = %Transaction{}) do
    if Transaction.verify_previous_signature?(tx) do
      :ok
    else
      {:error, "Invalid previous signature"}
    end
  end

  defp validate_contract(%Transaction{data: %TransactionData{code: ""}}), do: :ok

  defp validate_contract(%Transaction{
         data: %TransactionData{code: code, ownerships: ownerships}
       })
       when byte_size(code) <= @code_max_size do
    case Contracts.parse(code) do
      {:ok, %Contract{triggers: triggers}} when map_size(triggers) > 0 ->
        if Enum.any?(
             ownerships,
             &Ownership.authorized_public_key?(&1, Crypto.storage_nonce_public_key())
           ) do
          :ok
        else
          {:error, "Requires storage nonce public key as authorized public keys"}
        end

      {:ok, %Contract{}} ->
        :ok

      {:error, reason} ->
        {:error, "Smart contract invalid #{inspect(reason)}"}
    end
  end

  defp validate_contract(%Transaction{data: %TransactionData{code: code}})
       when byte_size(code) > @code_max_size do
    {:error, "Invalid contract type transaction , code exceed max size"}
  end

  @spec validate_ownerships(Transaction.t()) :: :ok | {:error, any()}
  defp validate_ownerships(%Transaction{data: %TransactionData{ownerships: []}}), do: :ok

  defp validate_ownerships(%Transaction{data: %TransactionData{ownerships: ownerships}}) do
    Enum.reduce_while(ownerships, :ok, fn
      %Ownership{secret: secret, authorized_keys: authorized_keys}, :ok ->
        cond do
          secret == "" ->
            {:halt, {:error, "Ownership: secret is empty"}}

          authorized_keys == %{} ->
            {:halt, {:error, "Ownership: authorized keys are empty"}}

          true ->
            verify_authorized_keys(authorized_keys)
        end
    end)
  end

  @spec verify_authorized_keys(authorized_keys :: map()) ::
          {:cont, :ok} | {:halt, {:error, any()}}
  defp verify_authorized_keys(authorized_keys) do
    # authorized_keys: %{(public_key :: Crypto.key()) => encrypted_key }

    Enum.reduce_while(authorized_keys, {:cont, :ok}, fn
      {"", _}, _ ->
        e = {:halt, {:error, "Ownership: public key is empty"}}
        {:halt, e}

      {_, ""}, _ ->
        e = {:halt, {:error, "Ownership: encrypted key is empty"}}
        {:halt, e}

      {public_key, _}, acc ->
        if Crypto.valid_public_key?(public_key),
          do: {:cont, acc},
          else: {:halt, {:halt, {:error, "Ownership: invalid public key"}}}
    end)
  end

  defp do_accept_transaction(
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

  defp do_accept_transaction(
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

  defp do_accept_transaction(
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

    genesis_address = DB.list_addresses_by_type(:mint_rewards) |> Stream.take(1) |> Enum.at(0)
    {last_network_pool_address, _} = DB.get_last_chain_address(genesis_address)

    previous_address = Transaction.previous_address(tx)

    time_validation =
      with {:ok, %Transaction{type: :node_rewards}} <-
             TransactionChain.get_transaction(previous_address, [:type]),
           {^last_network_pool_address, _} <-
             DB.get_last_chain_address(genesis_address, last_scheduling_date) do
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

  defp do_accept_transaction(
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
    with {:ok, ip, port, _http_port, _, _, origin_public_key, key_certificate} <-
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
           {:transfers, Enum.all?(token_transfers, &Reward.is_reward_token?(&1.token_address))} do
      :ok
    else
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
    end
  end

  defp do_accept_transaction(
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

  defp do_accept_transaction(
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

    {last_address, _} = DB.get_last_chain_address(genesis_address)

    sorted_authorized_keys =
      authorized_keys
      |> Map.keys()
      |> Enum.sort()

    sorted_node_renewal_authorized_keys =
      NodeRenewal.next_authorized_node_public_keys()
      |> Enum.sort()

    with {^last_address, _} <- DB.get_last_chain_address(genesis_address, last_scheduling_date),
         {:ok, _, _} <- NodeRenewal.decode_transaction_content(content),
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

  defp do_accept_transaction(%Transaction{type: :node_shared_secrets}, _) do
    {:error, "Invalid node shared secrets transaction"}
  end

  defp do_accept_transaction(
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

  defp do_accept_transaction(
         tx = %Transaction{
           type: :code_approval,
           data: %TransactionData{
             recipients: [proposal_address]
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

  defp do_accept_transaction(
         %Transaction{
           type: :code_approval,
           data: %TransactionData{
             recipients: []
           }
         },
         _
       ),
       do: {:error, "No recipient specified in code approval"}

  defp do_accept_transaction(
         %Transaction{
           type: :keychain,
           data: %TransactionData{content: "", ownerships: []}
         },
         _
       ) do
    {:error, "Invalid Keychain transaction"}
  end

  defp do_accept_transaction(
         %Transaction{
           type: :keychain,
           data: %TransactionData{content: content, ownerships: _ownerships}
         },
         _
       ) do
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

  defp do_accept_transaction(
         %Transaction{
           type: :keychain_access,
           data: %TransactionData{ownerships: []}
         },
         _
       ) do
    {:error, "Invalid Keychain access transaction"}
  end

  defp do_accept_transaction(
         %Transaction{
           type: :keychain_access,
           data: %TransactionData{ownerships: ownerships},
           previous_public_key: previous_public_key
         },
         _
       ) do
    if Enum.any?(ownerships, &Ownership.authorized_public_key?(&1, previous_public_key)) do
      :ok
    else
      {:error, "Invalid Keychain access transaction - Previous public key must be authorized"}
    end
  end

  defp do_accept_transaction(
         %Transaction{
           type: :token,
           data: %TransactionData{content: content}
         },
         _
       ) do
    verify_token_creation(content)
  end

  # To accept mint_rewards transaction, we ensure that the supply correspond to the
  # burned fees from the last summary and that there is no transaction since the last
  # reward schedule
  defp do_accept_transaction(
         %Transaction{
           type: :mint_rewards,
           data: %TransactionData{content: content}
         },
         _
       ) do
    total_fee = DB.get_latest_burned_fees()
    genesis_address = DB.list_addresses_by_type(:mint_rewards) |> Stream.take(1) |> Enum.at(0)
    {last_address, _} = DB.get_last_chain_address(genesis_address)

    with :ok <- verify_token_creation(content),
         {:ok, %{"supply" => ^total_fee}} <- Jason.decode(content),
         {^last_address, _} <-
           DB.get_last_chain_address(genesis_address, Reward.get_last_scheduling_date()) do
      :ok
    else
      {:ok, %{"supply" => _}} ->
        {:error, "The supply do not match burned fees from last summary"}

      {_, _} ->
        {:error, "There is already a mint rewards transaction since last schedule"}

      e ->
        e
    end
  end

  defp do_accept_transaction(
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

    {last_address, _} = DB.get_last_chain_address(genesis_address)

    with {^last_address, _} <-
           DB.get_last_chain_address(genesis_address, last_scheduling_date),
         true <- OracleChain.valid_services_content?(content) do
      :ok
    else
      {_, _} ->
        {:error, "Invalid oracle trigger time"}

      false ->
        {:error, "Invalid oracle transaction"}
    end
  end

  defp do_accept_transaction(
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

    {last_address, _} = DB.get_last_chain_address(genesis_address)

    transactions =
      TransactionChain.stream(previous_address, data: [:content], validation_stamp: [:timestamp])

    with {^last_address, _} <- DB.get_last_chain_address(genesis_address, last_scheduling_date),
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

  defp do_accept_transaction(%Transaction{type: :contract, data: %TransactionData{code: ""}}, _),
    do: {:error, "Invalid contract type transaction -  code is empty"}

  defp do_accept_transaction(
         %Transaction{type: :data, data: %TransactionData{content: "", ownerships: []}},
         _
       ),
       do: {:error, "Invalid data type transaction - Both content & ownership are empty"}

  defp do_accept_transaction(_, _), do: :ok

  defp validate_previous_transaction_type?(tx) do
    case Transaction.network_type?(tx.type) do
      false ->
        # not a network tx, no need to validate with last tx
        :ok

      true ->
        # when network tx, check with previous transaction
        if validate_network_chain?(tx.type, tx),
          do: :ok,
          else: {:error, "Invalid Transaction Type"}
    end
  end

  @spec validate_network_chain?(
          :code_approval
          | :code_proposal
          | :mint_rewards
          | :node
          | :node_rewards
          | :node_shared_secrets
          | :oracle
          | :oracle_summary
          | :origin,
          Archethic.TransactionChain.Transaction.t()
        ) :: boolean
  defp validate_network_chain?(type, tx = %Transaction{})
       when type in [:oracle, :oracle_summary] do
    # multipe txn chain based on summary date

    case OracleChain.genesis_address() do
      nil ->
        false

      gen_addr ->
        # first adddress found by looking up in the db
        first_addr =
          tx
          |> Transaction.previous_address()
          |> TransactionChain.get_genesis_address()

        # 1: tx gen & validated in current summary cycle, gen_addr.current must match
        # 2: tx gen in prev summary cycle &  validated in current summary cycle, gen_addr.prev must match
        # situation: the shift b/w summary A to summary B
        gen_addr.current |> elem(0) == first_addr ||
          gen_addr.prev |> elem(0) == first_addr
    end
  end

  defp validate_network_chain?(type, tx = %Transaction{})
       when type in [:mint_rewards, :node_rewards] do
    # singleton tx chain in network lifespan
    case Reward.genesis_address() do
      nil ->
        false

      gen_addr ->
        # first addr located in db by prev_address from tx
        first_addr =
          tx
          |> Transaction.previous_address()
          |> TransactionChain.get_genesis_address()

        gen_addr == first_addr
    end
  end

  defp validate_network_chain?(:node_shared_secrets, tx = %Transaction{}) do
    # singleton tx chain in network lifespan
    case SharedSecrets.genesis_address(:node_shared_secrets) do
      nil ->
        false

      gen_addr ->
        first_addr =
          tx
          |> Transaction.previous_address()
          |> TransactionChain.get_genesis_address()

        first_addr == gen_addr
    end
  end

  defp validate_network_chain?(:origin, tx = %Transaction{}) do
    # singleton tx chain in network lifespan
    # not parsing orgin pub key for origin family
    case SharedSecrets.genesis_address(:origin) do
      nil ->
        false

      origin_gen_addr_list ->
        first_addr_from_prev_addr =
          tx
          |> Transaction.previous_address()
          |> TransactionChain.get_genesis_address()

        first_addr_from_prev_addr in origin_gen_addr_list
    end
  end

  defp validate_network_chain?(_type, _tx), do: true

  defp verify_token_creation(content) do
    with {:ok, json_token} <- Jason.decode(content),
         :ok <- ExJsonSchema.Validator.validate(@token_schema, json_token),
         %{
           "type" => "non-fungible",
           "supply" => supply,
           "collection" => collection
         } <- json_token,
         {:decimals, 8} <- {:decimals, Map.get(json_token, "decimals", 8)},
         {:length, ^supply} <- {:length, length(collection) * @unit_uco},
         {:id, true} <- {:id, valid_collection_id?(collection)} do
      :ok
    else
      {:error, reason} ->
        {:error, "Invalid token transaction - Invalid specification #{inspect(reason)}"}

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
    |> P2P.nearest_nodes()
    |> Enum.filter(&Node.locally_available?/1)
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
