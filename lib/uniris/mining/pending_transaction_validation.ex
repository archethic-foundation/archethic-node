defmodule Uniris.Mining.PendingTransactionValidation do
  @moduledoc false

  alias Uniris.Contracts

  alias Uniris.Crypto

  alias Uniris.Governance
  alias Uniris.Governance.Code.Proposal, as: CodeProposal

  alias Uniris.OracleChain

  alias Uniris.P2P
  alias Uniris.P2P.Message.FirstPublicKey
  alias Uniris.P2P.Message.GetFirstPublicKey
  alias Uniris.P2P.Node

  alias Uniris.Replication

  alias Uniris.Reward

  alias Uniris.SharedSecrets

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Keys
  alias Uniris.TransactionChain.TransactionData.Ledger
  alias Uniris.TransactionChain.TransactionData.NFTLedger
  alias Uniris.TransactionChain.TransactionData.UCOLedger

  alias Uniris.Utils

  require Logger

  @doc """
  Determines if the transaction is accepted into the network
  """
  @spec validate(Transaction.t()) :: :ok | {:error, any()}
  def validate(tx = %Transaction{address: address, type: type}) do
    with true <- Transaction.verify_previous_signature?(tx),
         :ok <- validate_contract(tx),
         :ok <- validate_node_withdraw(tx),
         :ok <- validate_network_pool_transfers(tx) do
      do_accept_transaction(tx)
    else
      false ->
        Logger.error("Invalid previous signature",
          transaction: "#{type}@#{Base.encode16(address)}"
        )

        {:error, "Invalid previous signature"}

      {:error, _} = e ->
        e
    end
  end

  defp validate_contract(%Transaction{data: %TransactionData{code: ""}}), do: :ok

  defp validate_contract(%Transaction{
         address: address,
         type: type,
         data: %TransactionData{code: code, keys: keys}
       }) do
    with {:ok, _contract} <- Contracts.parse(code),
         true <- Crypto.storage_nonce_public_key() in Keys.list_authorized_keys(keys) do
      :ok
    else
      {:error, reason} ->
        Logger.error("Smart contract invalid #{inspect(reason)}",
          transaction: "#{type}@#{Base.encode16(address)}"
        )

        {:error, reason}

      false ->
        Logger.error("Require storage nonce public key as authorized keys",
          transaction: "#{type}@#{Base.encode16(address)}"
        )

        {:error, "Requires storage nonce public key as authorized keys"}
    end
  end

  defp validate_node_withdraw(%Transaction{
         address: address,
         type: type,
         data: %TransactionData{
           code: code,
           content: content,
           keys: keys,
           ledger: %Ledger{
             uco: %UCOLedger{transfers: uco_transfers},
             nft: %NFTLedger{transfers: nft_transfers}
           },
           recipients: recipients
         },
         previous_public_key: previous_public_key
       }) do
    from_node? =
      P2P.list_nodes()
      |> Enum.map(& &1.last_address)
      |> Enum.any?(&(&1 == Crypto.hash(previous_public_key)))

    if from_node? do
      network_pool_address = SharedSecrets.get_network_pool_address()

      with true <-
             Enum.any?(uco_transfers, &(&1.to == network_pool_address and &1.amount >= 0.0)),
           %Keys{secret: "", authorized_keys: %{}} <- keys,
           "" <- code,
           "" <- content,
           [] <- nft_transfers,
           [] <- recipients do
        :ok
      else
        false ->
          Logger.error("Node withdraw must transfer a part to the network pool",
            transaction: "#{type}@#{Base.encode16(address)}"
          )

          {:error, "Invalid transaction from node"}

        _ ->
          {:error, "Invalid transaction from node"}
      end
    else
      :ok
    end
  end

  defp validate_network_pool_transfers(%Transaction{
         address: address,
         type: type,
         data: %TransactionData{
           ledger: %Ledger{
             uco: %UCOLedger{transfers: uco_transfers},
             nft: %NFTLedger{transfers: nft_transfers}
           },
           code: code,
           content: content,
           recipients: recipients,
           keys: keys
         },
         previous_public_key: previous_public_key
       }) do
    network_pool_address = SharedSecrets.get_network_pool_address()

    if Crypto.hash(previous_public_key) == network_pool_address do
      with ^uco_transfers <- Reward.get_transfers_for_in_need_validation_nodes(),
           %Keys{secret: "", authorized_keys: %{}} <- keys,
           "" <- code,
           "" <- content,
           [] <- nft_transfers,
           [] <- recipients do
        :ok
      else
        _ ->
          Logger.error("Invalid network pool transfers",
            transaction: "#{type}@#{Base.encode16(address)}"
          )

          {:error, "Invalid network pool transfers"}
      end
    else
      :ok
    end
  end

  defp do_accept_transaction(%Transaction{
         address: address,
         type: :node,
         data: %TransactionData{
           content: content,
           ledger: %Ledger{uco: %UCOLedger{transfers: []}, nft: %NFTLedger{transfers: []}},
           recipients: [],
           code: "",
           keys: %Keys{secret: "", authorized_keys: %{}}
         }
       }) do
    case Regex.scan(Node.transaction_content_regex(), content, capture: :all_but_first) do
      [] ->
        Logger.error("Invalid node transaction content",
          transaction: "node@#{Base.encode16(address)}"
        )

        {:error, "Invalid node transaction"}

      _ ->
        :ok
    end
  end

  defp do_accept_transaction(%Transaction{type: :node}), do: {:error, "Invalid node transaction"}

  defp do_accept_transaction(%Transaction{
         address: address,
         type: :node_shared_secrets,
         data: %TransactionData{
           keys: keys = %Keys{secret: secret, authorized_keys: authorized_keys},
           ledger: %Ledger{uco: %UCOLedger{transfers: []}, nft: %NFTLedger{transfers: []}},
           recipients: [],
           code: ""
         }
       })
       when is_binary(secret) and byte_size(secret) > 0 and map_size(authorized_keys) > 0 do
    nodes = P2P.list_nodes()

    if Enum.all?(Keys.list_authorized_keys(keys), &Utils.key_in_node_list?(nodes, &1)) do
      :ok
    else
      Logger.error("Node shared secrets can only contains public node list",
        transaction: "node_shared_secrets@#{Base.encode16(address)}"
      )

      {:error, "Invalid node shared secrets transaction"}
    end
  end

  defp do_accept_transaction(%Transaction{type: :node_shared_secrets}) do
    {:error, "Invalid node shared secrets transaction"}
  end

  defp do_accept_transaction(
         tx = %Transaction{
           address: address,
           type: :code_proposal,
           data: %TransactionData{
             ledger: %Ledger{uco: %UCOLedger{transfers: []}, nft: %NFTLedger{transfers: []}},
             code: ""
           }
         }
       ) do
    with {:ok, prop} <- CodeProposal.from_transaction(tx),
         true <- Governance.valid_code_changes?(prop) do
      :ok
    else
      _ ->
        Logger.error("Invalid code proposal",
          transaction: "code_proposal@#{Base.encode16(address)}"
        )

        {:error, "Invalid code proposal"}
    end
  end

  defp do_accept_transaction(%Transaction{type: :code_proposal}),
    do: {:error, "Invalid code proposal transaction"}

  defp do_accept_transaction(
         tx = %Transaction{
           address: address,
           type: :code_approval,
           data: %TransactionData{
             ledger: %Ledger{uco: %UCOLedger{transfers: []}, nft: %NFTLedger{transfers: []}},
             code: "",
             recipients: [proposal_address]
           }
         }
       ) do
    first_public_key = get_first_public_key(tx)

    with {:member, true} <-
           {:member, Governance.pool_member?(first_public_key, :technical_council)},
         {:ok, prop} <- Governance.get_code_proposal(proposal_address),
         previous_address <- Transaction.previous_address(tx),
         {:signed, false} <- {:signed, CodeProposal.signed_by?(prop, previous_address)} do
      :ok
    else
      {:member, false} ->
        Logger.error("No technical council member",
          transaction: "code_approval@#{Base.encode16(address)}"
        )

        {:error, "No technical council member"}

      {:error, :not_found} ->
        Logger.error("Code proposal does not exist",
          transaction: "code_approval@#{Base.encode16(address)}"
        )

        {:error, "Code proposal doest not exist"}

      {:signed, true} ->
        Logger.error("Code proposal already signed",
          transaction: "code_approval@#{Base.encode16(address)}"
        )

        {:error, "Code proposal already signed"}
    end
  end

  defp do_accept_transaction(%Transaction{type: :code_approval}),
    do: {:error, "Invalid code approval transaction"}

  defp do_accept_transaction(%Transaction{
         address: address,
         type: :nft,
         data: %TransactionData{content: content}
       }) do
    if Regex.match?(~r/(?<=initial supply:).*\d/mi, content) do
      :ok
    else
      Logger.error("Invalid NFT transaction content", transaction: "nft@#{Base.encode16(address)}")

      {:error, "Invalid NFT content"}
    end
  end

  defp do_accept_transaction(%Transaction{
         address: address,
         type: :oracle,
         data: %TransactionData{
           content: content,
           ledger: %Ledger{uco: %UCOLedger{transfers: []}, nft: %NFTLedger{transfers: []}},
           code: "",
           keys: %Keys{secret: "", authorized_keys: %{}},
           recipients: []
         }
       }) do
    if OracleChain.valid_services_content?(content) do
      :ok
    else
      Logger.error("Invalid oracle transaction", transaction: "oracle@#{Base.encode16(address)}")
      {:error, "Invalid oracle transaction"}
    end
  end

  defp do_accept_transaction(%Transaction{type: :oracle}),
    do: {:error, "Invalid oracle transaction"}

  defp do_accept_transaction(%Transaction{
         address: address,
         type: :oracle_summary,
         data: %TransactionData{
           content: content,
           ledger: %Ledger{uco: %UCOLedger{transfers: []}, nft: %NFTLedger{transfers: []}},
           code: "",
           keys: %Keys{secret: "", authorized_keys: %{}},
           recipients: []
         },
         previous_public_key: previous_public_key
       }) do
    with previous_address <- Crypto.hash(previous_public_key),
         oracle_chain <- TransactionChain.get(previous_address, data: [:content]),
         false <- Enum.empty?(oracle_chain),
         true <- OracleChain.valid_summary?(content, oracle_chain) do
      :ok
    else
      true ->
        Logger.error("Oracle transaction summary cannot process with an empty chain",
          transaction: "oracle_summary@#{Base.encode16(address)}"
        )

        {:error, "Invalid oracle summary transaction"}

      _ ->
        Logger.error("Invalid oracle summary transaction",
          transaction: "oracle_summary@#{Base.encode16(address)}"
        )

        {:error, "Invalid oracle summary transaction"}
    end
  end

  defp do_accept_transaction(%Transaction{type: :oracle_summary}),
    do: {:error, "Invalid oracle summary transaction"}

  defp do_accept_transaction(_), do: :ok

  defp get_first_public_key(tx = %Transaction{previous_public_key: previous_public_key}) do
    previous_address = Transaction.previous_address(tx)

    storage_nodes = Replication.chain_storage_nodes(previous_address)

    response_message =
      P2P.reply_first(storage_nodes, %GetFirstPublicKey{address: previous_address})

    case response_message do
      {:ok, %FirstPublicKey{public_key: public_key}} ->
        public_key

      _ ->
        previous_public_key
    end
  end
end
