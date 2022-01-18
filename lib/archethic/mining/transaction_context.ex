defmodule ArchEthic.Mining.TransactionContext do
  @moduledoc """
  Gathering of the necessary information for the transaction validation:
  - previous transaction
  - unspent outputs
  """

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  alias __MODULE__.DataFetcher
  alias __MODULE__.NodeDistribution

  alias ArchEthic.Replication

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

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
          validation_node_public_keys :: list(Crypto.key())
        ) ::
          {Transaction.t(), list(UnspentOutput.t()), list(Node.t()), bitstring(), bitstring(),
           bitstring()}
  def get(
        previous_address,
        chain_storage_node_public_keys,
        beacon_storage_nodes_public_keys,
        validation_node_public_keys
      ) do
    nodes_distribution = previous_nodes_distribution(previous_address, 5, 3)

    context =
      wrap_async_queries(
        previous_address,
        chain_storage_node_public_keys,
        beacon_storage_nodes_public_keys,
        validation_node_public_keys,
        nodes_distribution
      )
      |> Enum.reduce(%{}, &reduce_tasks/2)

    {
      Map.get(context, :previous_transaction),
      Map.get(context, :unspent_outputs, []),
      Map.get(context, :previous_storage_nodes, []),
      Map.get(context, :chain_storage_nodes_view, <<>>),
      Map.get(context, :beacon_storage_nodes_view, <<>>),
      Map.get(context, :validation_nodes_view, <<>>)
    }
  end

  defp previous_nodes_distribution(previous_address, nb_sub_lists, sample_size) do
    node_list = P2P.unprioritize_node(P2P.available_nodes(), Crypto.first_node_public_key())

    previous_address
    |> Replication.chain_storage_nodes(node_list)
    |> P2P.nearest_nodes()
    |> Enum.filter(&Node.locally_available?/1)
    |> NodeDistribution.split_storage_nodes(nb_sub_lists, sample_size)
  end

  defp wrap_async_queries(
         previous_address,
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
      prev_tx: fn ->
        DataFetcher.fetch_previous_transaction(previous_address, prev_tx_nodes_split)
      end,
      utxo: fn ->
        DataFetcher.fetch_unspent_outputs(
          previous_address,
          unspent_outputs_nodes_split
        )
      end,
      chain_nodes_view: fn ->
        DataFetcher.fetch_p2p_view(
          chain_storage_node_public_keys,
          chain_storage_nodes_view_split
        )
      end,
      beacon_nodes_view: fn ->
        DataFetcher.fetch_p2p_view(
          beacon_storage_nodes_public_keys,
          beacon_storage_nodes_view_split
        )
      end,
      validation_nodes_view: fn ->
        DataFetcher.fetch_p2p_view(validation_node_public_keys, validation_nodes_view_split)
      end
    ]
    |> Task.async_stream(
      fn {domain, fun} ->
        {domain, fun.()}
      end,
      on_timeout: :kill_task
    )
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Stream.map(&elem(&1, 1))
  end

  defp reduce_tasks({_, {:error, _}}, acc), do: acc

  defp reduce_tasks(
         {:prev_tx, {:ok, prev_tx = %Transaction{}, node = %Node{}}},
         acc
       ) do
    acc
    |> Map.put(:previous_transaction, prev_tx)
    |> Map.update(
      :previous_storage_nodes,
      [node],
      &P2P.distinct_nodes([node | &1])
    )
  end

  defp reduce_tasks({:utxo, {:ok, unspent_outputs, node = %Node{}}}, acc) do
    acc
    |> Map.put(:unspent_outputs, unspent_outputs)
    |> Map.update(
      :previous_storage_nodes,
      [node],
      &P2P.distinct_nodes([node | &1])
    )
  end

  defp reduce_tasks({:chain_nodes_view, {:ok, view, node = %Node{}}}, acc) do
    acc
    |> Map.put(:chain_storage_nodes_view, view)
    |> Map.update(
      :previous_storage_nodes,
      [node],
      &P2P.distinct_nodes([node | &1])
    )
  end

  defp reduce_tasks({:beacon_nodes_view, {:ok, view, node = %Node{}}}, acc) do
    acc
    |> Map.put(:beacon_storage_nodes_view, view)
    |> Map.update(
      :previous_storage_nodes,
      [node],
      &P2P.distinct_nodes([node | &1])
    )
  end

  defp reduce_tasks({:validation_nodes_view, {:ok, view, node = %Node{}}}, acc) do
    acc
    |> Map.put(:validation_nodes_view, view)
    |> Map.update(
      :previous_storage_nodes,
      [node],
      &P2P.distinct_nodes([node | &1])
    )
  end
end
