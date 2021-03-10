defmodule Uniris.SelfRepair.Sync.BeaconSummaryHandler.TransactionHandler do
  @moduledoc false

  alias Uniris.BeaconChain.Slot.TransactionSummary

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetTransaction

  alias Uniris.Replication

  alias Uniris.TransactionChain.Transaction

  alias Uniris.Utils

  require Logger

  @doc """
  Sort the transactions info by prioritize by transaction type weight and timestamp.

  Transaction type precedence order:
  - Node (Weight: 1)
  - Node shared secrets (Weight: 2)
  - Origin shared secrets (Weight: 3)
  - Code proposal (Weight: 4)
  - Oracle (Weight: 5)
  - Oracle Summary (Weight: 6)
  - Anything else (Weight: 10)

  ## Examples

      iex> [
      ...>   %TransactionSummary{address: "@Alice2", type: :transfer, timestamp: ~U[2020-10-14 14:38:08.657279Z] },
      ...>   %TransactionSummary{address: "@Code2", type: :code_proposal, timestamp: ~U[2020-10-14 14:37:58.657279Z]},
      ...>   %TransactionSummary{address: "@NodeSharedSecrets10", type: :node_shared_secrets, timestamp: ~U[2020-10-14 14:40:28.657279Z]},
      ...>   %TransactionSummary{address: "@NodeSharedSecrets11", type: :node_shared_secrets, timestamp: ~U[2020-10-15 14:40:28.657279Z]},
      ...>   %TransactionSummary{address: "@Bob4", type: :transfer, timestamp: ~U[2020-10-14 14:38:18.657279Z] },
      ...>   %TransactionSummary{address: "@Node5", type: :node, timestamp: ~U[2020-10-14 14:39:48.657279Z]},
      ...>   %TransactionSummary{address: "@Node10", type: :node, timestamp: ~U[2020-10-14 14:43:08.657279Z]},
      ...>   %TransactionSummary{address: "@Oracle1", type: :oracle, timestamp: ~U[2020-10-14 08:43:08Z]},
      ...>   %TransactionSummary{address: "@Oracle2", type: :oracle, timestamp: ~U[2020-10-14 14:43:08Z]},
      ...>   %TransactionSummary{address: "@OracleSummary1", type: :oracle_summary, timestamp: ~U[2020-10-15 00:00:00Z]}
      ...> ]
      ...> |> TransactionHandler.sort_transactions_information()
      [
        %TransactionSummary{address: "@Node5", type: :node, timestamp: ~U[2020-10-14 14:39:48.657279Z]},
        %TransactionSummary{address: "@Node10", type: :node, timestamp: ~U[2020-10-14 14:43:08.657279Z]},
        %TransactionSummary{address: "@NodeSharedSecrets10", type: :node_shared_secrets, timestamp: ~U[2020-10-14 14:40:28.657279Z]},
        %TransactionSummary{address: "@NodeSharedSecrets11", type: :node_shared_secrets, timestamp: ~U[2020-10-15 14:40:28.657279Z]},
        %TransactionSummary{address: "@Code2", type: :code_proposal, timestamp: ~U[2020-10-14 14:37:58.657279Z]},
        %TransactionSummary{address: "@Oracle1", type: :oracle, timestamp: ~U[2020-10-14 08:43:08Z]},
        %TransactionSummary{address: "@Oracle2", type: :oracle, timestamp: ~U[2020-10-14 14:43:08Z]},
        %TransactionSummary{address: "@OracleSummary1", type: :oracle_summary, timestamp: ~U[2020-10-15 00:00:00Z]},
        %TransactionSummary{address: "@Alice2", type: :transfer, timestamp: ~U[2020-10-14 14:38:08.657279Z] },
        %TransactionSummary{address: "@Bob4", type: :transfer, timestamp: ~U[2020-10-14 14:38:18.657279Z] }
      ]
  """
  @spec sort_transactions_information(list(TransactionSummary.t()) | Enumerable.t()) ::
          list(TransactionSummary.t())
  def sort_transactions_information(txs_info) do
    Enum.sort_by(txs_info, &{weight_transaction_type(&1.type), &1.timestamp})
  end

  defp weight_transaction_type(:node), do: 1
  defp weight_transaction_type(:node_shared_secrets), do: 2
  defp weight_transaction_type(:origin_shared_secrets), do: 3
  defp weight_transaction_type(:code_proposal), do: 4
  defp weight_transaction_type(:oracle), do: 5
  defp weight_transaction_type(:oracle_summary), do: 6
  defp weight_transaction_type(_), do: 10

  @doc """
  Determine if the transaction should be downloaded by the local node.

  Verify firstly the chain storage nodes election.
  If not successful, perform storage nodes election based on the transaction movements.
  """
  @spec download_transaction?(TransactionSummary.t()) :: boolean()
  def download_transaction?(%TransactionSummary{
        address: address,
        type: type,
        movements_addresses: mvt_addresses
      }) do
    chain_storage_nodes = Replication.chain_storage_nodes(address, type, P2P.list_nodes())

    if Utils.key_in_node_list?(chain_storage_nodes, Crypto.node_public_key(0)) do
      true
    else
      Enum.any?(mvt_addresses, fn address ->
        io_storage_nodes = Replication.chain_storage_nodes(address, P2P.list_nodes())
        node_pool_address = Crypto.hash(Crypto.node_public_key())

        Utils.key_in_node_list?(io_storage_nodes, Crypto.node_public_key(0)) or
          address == node_pool_address
      end)
    end
  end

  @doc """
  Request the transaction for the closest storage nodes and replicate it locally.
  """
  @spec download_transaction(TransactionSummary.t(), patch :: binary()) ::
          :ok | {:error, :invalid_transaction}
  def download_transaction(%TransactionSummary{address: address, type: type}, node_patch)
      when is_binary(node_patch) do
    Logger.info("Synchronize missed transaction", transaction: "#{type}@#{Base.encode16(address)}")

    response =
      address
      |> Replication.chain_storage_nodes(type, P2P.list_nodes())
      |> Enum.reject(&(&1.first_public_key == Crypto.node_public_key(0)))
      |> P2P.reply_first(%GetTransaction{address: address})

    case response do
      {:ok, tx = %Transaction{}} ->
        roles =
          [
            chain:
              Replication.chain_storage_node?(tx, Crypto.node_public_key(), P2P.list_nodes()),
            IO: Replication.io_storage_node?(tx, Crypto.node_public_key(), P2P.list_nodes())
          ]
          |> Utils.get_keys_from_value_match(true)

        case Replication.process_transaction(tx, roles, self_repair?: true) do
          :ok ->
            :ok

          {:error, :invalid_transaction} = e ->
            e
        end

      _ ->
        Logger.error("Not enough nodes to satisfy the self repair transaction handling",
          transaction: Base.encode16(address)
        )
    end
  end
end
