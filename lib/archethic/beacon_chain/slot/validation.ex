defmodule ArchEthic.BeaconChain.Slot.Validation do
  @moduledoc false

  alias ArchEthic.BeaconChain.Slot
  alias ArchEthic.BeaconChain.Slot.EndOfNodeSync
  alias ArchEthic.BeaconChain.Slot.TransactionSummary

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.GetTransactionSummary
  alias ArchEthic.P2P.Message.NotFound
  alias ArchEthic.P2P.Node

  alias ArchEthic.Replication

  require Logger

  @doc """
  Validate the transaction summaries to ensure the transactions included really exists
  """
  @spec valid_transaction_summaries?(Slot.t()) :: boolean()
  def valid_transaction_summaries?(%Slot{transaction_summaries: transaction_summaries}) do
    Task.async_stream(transaction_summaries, &do_valid_transaction_summary/1,
      ordered: false,
      on_timeout: :kill_task
    )
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.into([], fn {:ok, res} -> res end)
    |> Enum.all?(&match?(true, &1))
  end

  defp do_valid_transaction_summary(
         summary = %TransactionSummary{address: address, timestamp: timestamp}
       ) do
    storage_nodes = transaction_summary_storage_nodes(address, timestamp)

    case check_transaction_summary(storage_nodes, address, summary) do
      :ok ->
        true

      {:error, _} ->
        false
    end
  end

  defp check_transaction_summary(nodes, address, expected_summary, timeout \\ 500)

  defp check_transaction_summary(
         [node | rest],
         address,
         expected_summary,
         timeout
       ) do
    case P2P.send_message(node, %GetTransactionSummary{address: address}, timeout) do
      {:ok, ^expected_summary} ->
        :ok

      {:ok, recv = %TransactionSummary{}} ->
        Logger.debug(
          "BeaconChain summary received is different #{inspect(recv)} - expect #{expected_summary}"
        )

        {:error, :invalid_summary}

      {:ok, %NotFound{}} ->
        Logger.debug("BeaconChain summary was not found at #{Node.endpoint(node)}")
        check_transaction_summary(rest, address, expected_summary, timeout)

      {:error, :timeout} ->
        check_transaction_summary(rest, address, expected_summary, trunc(timeout * 1.5))

      {:error, :closed} ->
        check_transaction_summary(rest, address, expected_summary, timeout)
    end
  end

  defp check_transaction_summary([], _, _, _), do: {:error, :network_issue}

  defp transaction_summary_storage_nodes(address, timestamp) do
    address
    |> Replication.chain_storage_nodes()
    |> Enum.filter(fn %Node{enrollment_date: enrollment_date} ->
      DateTime.compare(DateTime.truncate(enrollment_date, :second), timestamp) == :lt
    end)
    |> P2P.nearest_nodes()
    |> P2P.unprioritize_node(Crypto.first_node_public_key())
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
