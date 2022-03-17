defmodule ArchEthic.Mining.PendingTransactionValidation do
  @moduledoc false

  alias ArchEthic.Contracts
  alias ArchEthic.Contracts.Contract

  alias ArchEthic.Crypto

  alias ArchEthic.Election

  alias ArchEthic.Governance
  alias ArchEthic.Governance.Code.Proposal, as: CodeProposal
  alias ArchEthic.Networking
  alias ArchEthic.OracleChain

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.FirstPublicKey
  alias ArchEthic.P2P.Message.GetFirstPublicKey
  alias ArchEthic.P2P.Node

  alias ArchEthic.Reward

  alias ArchEthic.SharedSecrets.NodeRenewal

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.Ownership
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger

  alias ArchEthic.Utils

  require Logger

  @doc """
  Determines if the transaction is accepted into the network
  """
  @spec validate(Transaction.t()) :: :ok | {:error, any()}
  def validate(tx = %Transaction{address: address, type: type}) do
    start = System.monotonic_time()

    with true <- Transaction.verify_previous_signature?(tx),
         :ok <- validate_contract(tx),
         :ok <- validate_content_size(tx),
         :ok <- do_accept_transaction(tx) do
      :telemetry.execute(
        [:archethic, :mining, :pending_transaction_validation],
        %{duration: System.monotonic_time() - start},
        %{transaction_type: type}
      )

      :ok
    else
      false ->
        Logger.error("Invalid previous signature",
          transaction_address: Base.encode16(address),
          transaction_type: type
        )

        {:error, "Invalid previous signature"}

      {:error, reason} = e ->
        Logger.info(reason, transaction_address: Base.encode16(address), transaction_type: type)
        e
    end
  end

  defp validate_content_size(%Transaction{data: %TransactionData{content: content}}) do
    content_max_size = Application.get_env(:archethic, :transaction_data_content_max_size)

    if byte_size(content) >= content_max_size do
      {:error, "Invalid node transaction with content size greaterthan content_max_size"}
    else
      :ok
    end
  end

  defp validate_contract(%Transaction{data: %TransactionData{code: ""}}), do: :ok

  defp validate_contract(%Transaction{
         data: %TransactionData{code: code, ownerships: ownerships}
       }) do
    case Contracts.parse(code) do
      {:ok, %Contract{triggers: [_ | _]}} ->
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

  defp do_accept_transaction(%Transaction{
         type: :node_rewards,
         data: %TransactionData{
           ledger: %Ledger{
             uco: %UCOLedger{transfers: uco_transfers}
           }
         }
       }) do
    case Reward.get_transfers_for_in_need_validation_nodes(Reward.last_scheduling_date()) do
      ^uco_transfers ->
        :ok

      _ ->
        {:error, "Invalid network pool transfers"}
    end
  end

  defp do_accept_transaction(%Transaction{
         type: :node,
         data: %TransactionData{
           content: content
         },
         previous_public_key: previous_public_key
       }) do
    with {:ok, ip, port, _http_port, _, _, key_certificate} <-
           Node.decode_transaction_content(content),
         {:auth_origin, true} <-
           {:auth_origin,
            Crypto.authorized_key_origin?(previous_public_key, get_allowed_node_key_origins())},
         root_ca_public_key <- Crypto.get_root_ca_public_key(previous_public_key),
         {:auth_cert, true} <-
           {:auth_cert,
            Crypto.verify_key_certificate?(
              previous_public_key,
              key_certificate,
              root_ca_public_key
            )},
         {:conn, true} <-
           {:conn, valid_connection?(ip, port, previous_public_key, should_validate_node_ip?())} do
      :ok
    else
      :error ->
        {:error, "Invalid node transaction's content"}

      {:auth_cert, false} ->
        {:error, "Invalid node transaction with invalid certificate"}

      {:auth_origin, false} ->
        {:error, "Invalid node transaction with invalid key origin"}

      {:conn, false} ->
        {:error, "Invalid node connection (IP/Port) for the given public key"}
    end
  end

  defp do_accept_transaction(%Transaction{
         type: :node_shared_secrets,
         data: %TransactionData{
           content: content,
           ownerships: [%Ownership{secret: secret, authorized_keys: authorized_keys}]
         }
       })
       when is_binary(secret) and byte_size(secret) > 0 and map_size(authorized_keys) > 0 do
    nodes = P2P.available_nodes()

    with {:ok, _, _} <- NodeRenewal.decode_transaction_content(content),
         true <- Enum.all?(Map.keys(authorized_keys), &Utils.key_in_node_list?(nodes, &1)) do
      :ok
    else
      :error ->
        {:error, "Invalid node shared secrets transaction content"}

      false ->
        {:error, "Invalid node shared secrets transaction authorized nodes"}
    end
  end

  defp do_accept_transaction(%Transaction{type: :node_shared_secrets}) do
    {:error, "Invalid node shared secrets transaction"}
  end

  defp do_accept_transaction(
         tx = %Transaction{
           type: :code_proposal
         }
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
         }
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

  defp do_accept_transaction(%Transaction{
         type: :nft,
         data: %TransactionData{content: content}
       }) do
    if Regex.match?(~r/(?<=initial supply:).*\d/mi, content) do
      :ok
    else
      {:error, "Invalid NFT content"}
    end
  end

  defp do_accept_transaction(%Transaction{
         type: :oracle,
         data: %TransactionData{
           content: content
         }
       }) do
    if OracleChain.valid_services_content?(content) do
      :ok
    else
      {:error, "Invalid oracle transaction"}
    end
  end

  defp do_accept_transaction(%Transaction{
         type: :oracle_summary,
         data: %TransactionData{
           content: content
         },
         previous_public_key: previous_public_key
       }) do
    with previous_address <- Crypto.derive_address(previous_public_key),
         oracle_chain <-
           TransactionChain.get(previous_address, data: [:content], validation_stamp: [:timestamp]),
         true <- OracleChain.valid_summary?(content, oracle_chain) do
      :ok
    else
      _ ->
        {:error, "Invalid oracle summary transaction"}
    end
  end

  defp do_accept_transaction(_), do: :ok

  defp get_allowed_node_key_origins do
    :archethic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:allowed_node_key_origins, [])
  end

  defp get_first_public_key(tx = %Transaction{}) do
    previous_address = Transaction.previous_address(tx)

    previous_address
    |> Election.chain_storage_nodes(P2P.available_nodes())
    |> P2P.nearest_nodes()
    |> Enum.filter(&Node.locally_available?/1)
    |> get_first_public_key(previous_address)
  end

  defp get_first_public_key([node | rest], address) do
    case P2P.send_message(node, %GetFirstPublicKey{address: address}) do
      {:ok, %FirstPublicKey{public_key: public_key}} ->
        {:ok, public_key}

      {:error, _} ->
        get_first_public_key(rest, address)
    end
  end

  defp get_first_public_key([], _), do: {:error, :network_issue}

  defp valid_connection?(ip, port, previous_public_key, _check_ip? = true) do
    with true <- Networking.valid_ip?(ip),
         false <- P2P.duplicating_node?(ip, port, previous_public_key) do
      true
    else
      _ ->
        false
    end
  end

  defp valid_connection?(ip, port, previous_public_key, _check_ip? = false) do
    case P2P.duplicating_node?(ip, port, previous_public_key) do
      false ->
        true

      true ->
        false
    end
  end

  defp should_validate_node_ip? do
    :archethic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:validate_node_ip, false)
  end
end
