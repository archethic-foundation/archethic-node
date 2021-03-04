defmodule Uniris.Mining.TransactionContext do
  @moduledoc """
  Gathering of the necessary information for the transaction validation:
  - previous transaction
  - unspent outputs
  """

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias __MODULE__.DataFetcher
  alias __MODULE__.NodeDistribution

  alias Uniris.Replication

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  require Logger

  @doc """
  Request concurrently the context of the transaction including the previous transaction,
  the unspent outputs and P2P view for the storage nodes and validation nodes
  as long as the involved nodes for the retrieval
  """
  @spec get(
          previous_tx_address :: binary(),
          chain_storage_node_public_keys :: list(Crypto.key()),
          beacon_storage_nodes_public_keys :: list(Crypto.key()),
          validation_node_public_keys :: list(Crypto.key()),
          unspent_outputs_confirmation? :: boolean()
        ) ::
          {Transaction.t(), list(UnspentOutput.t()), list(Node.t()), bitstring(), bitstring(),
           bitstring()}
  def get(
        previous_address,
        chain_storage_node_public_keys,
        beacon_storage_nodes_public_keys,
        validation_node_public_keys,
        unspent_outputs_confirmation? \\ true
      ) do
    nodes_distribution = previous_nodes_distribution(previous_address, 5, 3)

    context =
      wrap_async_queries(
        previous_address,
        unspent_outputs_confirmation?,
        chain_storage_node_public_keys,
        beacon_storage_nodes_public_keys,
        validation_node_public_keys,
        nodes_distribution
      )
      |> Task.yield_many()
      |> Enum.reduce(%{}, &reduce_tasks/2)

    {
      Map.get(context, :previous_transaction),
      Map.get(context, :unspent_outputs),
      Map.get(context, :previous_storage_nodes),
      Map.get(context, :chain_storage_nodes_view),
      Map.get(context, :beacon_storage_nodes_view),
      Map.get(context, :validation_nodes_view)
    }
  end

  defp previous_nodes_distribution(previous_address, nb_sub_lists, sample_size) do
    previous_address
    |> Replication.chain_storage_nodes(P2P.list_nodes(availability: :global))
    |> NodeDistribution.split_storage_nodes(nb_sub_lists, sample_size)
  end

  defp wrap_async_queries(
         previous_address,
         unspent_outputs_confirmation?,
         chain_storage_node_public_keys,
         beacon_storage_nodes_public_keys,
         validation_node_public_keys,
         _nodes_distribution = [
           prev_tx_nodes_split,
           unspent_outputs_nodes_split,
           chain_storage_nodes_view_split,
           beacon_storage_nodes_view_split,
           validation_nodes_view_split
         ]
       ) do
    [
      Task.async(fn ->
        DataFetcher.fetch_previous_transaction(previous_address, prev_tx_nodes_split)
      end),
      Task.async(fn ->
        DataFetcher.fetch_unspent_outputs(
          previous_address,
          unspent_outputs_nodes_split,
          unspent_outputs_confirmation?
        )
      end),
      Task.async(fn ->
        {:chain,
         DataFetcher.fetch_p2p_view(
           chain_storage_node_public_keys,
           chain_storage_nodes_view_split
         )}
      end),
      Task.async(fn ->
        {:beacon,
         DataFetcher.fetch_p2p_view(
           beacon_storage_nodes_public_keys,
           beacon_storage_nodes_view_split
         )}
      end),
      Task.async(fn ->
        {:validation,
         DataFetcher.fetch_p2p_view(validation_node_public_keys, validation_nodes_view_split)}
      end)
    ]
  end

  defp reduce_tasks(
         {%Task{}, {:ok, {:ok, prev_tx = %Transaction{}, prev_tx_node = %Node{}}}},
         acc
       ) do
    acc
    |> Map.put(:previous_transaction, prev_tx)
    |> Map.update(
      :previous_storage_nodes,
      [prev_tx_node],
      &P2P.distinct_nodes([prev_tx_node | &1])
    )
  end

  defp reduce_tasks({%Task{}, {:ok, {:error, :not_found}}}, acc), do: acc

  defp reduce_tasks({%Task{}, {:ok, {unspent_outputs, unspent_outputs_nodes}}}, acc)
       when is_list(unspent_outputs) and is_list(unspent_outputs_nodes) do
    acc
    |> Map.put(:unspent_outputs, unspent_outputs)
    |> Map.update(
      :previous_storage_nodes,
      unspent_outputs_nodes,
      &P2P.distinct_nodes(&1 ++ unspent_outputs_nodes)
    )
  end

  defp reduce_tasks({%Task{}, {:ok, {:chain, {view, node = %Node{}}}}}, acc) do
    acc
    |> Map.put(:chain_storage_nodes_view, view)
    |> Map.update(
      :previous_storage_nodes,
      [node],
      &P2P.distinct_nodes([node | &1])
    )
  end

  defp reduce_tasks({%Task{}, {:ok, {:beacon, {view, node = %Node{}}}}}, acc) do
    acc
    |> Map.put(:beacon_storage_nodes_view, view)
    |> Map.update(
      :previous_storage_nodes,
      [node],
      &P2P.distinct_nodes([node | &1])
    )
  end

  defp reduce_tasks({%Task{}, {:ok, {:validation, {view, node = %Node{}}}}}, acc) do
    acc
    |> Map.put(:validation_nodes_view, view)
    |> Map.update(
      :previous_storage_nodes,
      [node],
      &P2P.distinct_nodes([node | &1])
    )
  end
end
