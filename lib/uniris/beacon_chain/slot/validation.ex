defmodule Uniris.BeaconChain.Slot.Validation do
  @moduledoc false

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.EndOfNodeSync
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.SummaryTimer

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetTransactionSummary
  alias Uniris.P2P.Node

  alias Uniris.Replication

  @doc """
  Validate the transaction summaries to ensure the transactions included really exists
  """
  @spec valid_transaction_summaries?(Slot.t()) :: boolean()
  def valid_transaction_summaries?(%Slot{transaction_summaries: transaction_summaries}) do
    Task.async_stream(transaction_summaries, &do_valid_transaction_summary/1,
      ordered: false,
      on_timeout: :kill_task
    )
    |> Enum.into([], fn {:ok, res} -> res end)
    |> Enum.all?(&match?(true, &1))
  end

  defp do_valid_transaction_summary(
         summary = %TransactionSummary{address: address, timestamp: timestamp}
       ) do
    case transaction_summary_storage_nodes(address, timestamp) do
      [] ->
        true

      nodes ->
        case P2P.reply_atomic(nodes, 3, %GetTransactionSummary{address: address}) do
          {:ok, ^summary} ->
            true

          _ ->
            false
        end
    end
  end

  defp transaction_summary_storage_nodes(address, timestamp) do
    address
    |> Replication.chain_storage_nodes()
    |> Enum.filter(fn %Node{enrollment_date: enrollment_date} ->
      previous_summary_time = SummaryTimer.previous_summary(timestamp)

      diff = DateTime.compare(DateTime.truncate(enrollment_date, :second), previous_summary_time)

      diff == :lt or diff == :eq
    end)
    |> Enum.reject(&(&1.first_public_key == Crypto.first_node_public_key()))
  end

  @doc """
  Validate the end of node synchronization to ensure the list of nodes exists
  """
  @spec valid_end_of_node_sync?(Slot.t()) :: boolean
  def valid_end_of_node_sync?(%Slot{end_of_node_synchronizations: end_of_node_sync}) do
    Enum.all?(end_of_node_sync, fn %EndOfNodeSync{public_key: key} ->
      match?({:ok, %Node{first_public_key: ^key}}, P2P.get_node_info(key))
    end)
  end
end
