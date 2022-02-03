defmodule ArchEthic.Mining.TransactionContext do
  @moduledoc """
  Gathering of the necessary information for the transaction validation:
  - previous transaction
  - unspent outputs
  """

  alias ArchEthic.Crypto

  alias ArchEthic.Election

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  alias __MODULE__.DataFetcher
  alias __MODULE__.NodeDistribution

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
          beacon_storage_nodes_public_keys :: list(Crypto.key())
        ) ::
          {Transaction.t(), list(UnspentOutput.t()), list(Node.t()), bitstring(), bitstring()}
  def get(
        previous_address,
        chain_storage_node_public_keys,
        beacon_storage_node_public_keys
      ) do
    nodes_distribution = previous_nodes_distribution(previous_address, 2, 3)

    node_public_keys =
      (chain_storage_node_public_keys ++
         beacon_storage_node_public_keys)
      |> Enum.uniq()
      |> Enum.sort()

    {prev_tx, utxos, nodes_view, involved_nodes} =
      wrap_async_queries(
        previous_address,
        node_public_keys,
        nodes_distribution
      )

    {chain_storage_nodes_view, beacon_storage_nodes_view} =
      aggregate_views(
        nodes_view,
        node_public_keys,
        chain_storage_node_public_keys,
        beacon_storage_node_public_keys
      )

    {prev_tx, utxos, involved_nodes, chain_storage_nodes_view, beacon_storage_nodes_view}
  end

  defp previous_nodes_distribution(previous_address, nb_sub_lists, sample_size) do
    node_list = P2P.unprioritize_node(P2P.available_nodes(), Crypto.first_node_public_key())

    previous_address
    |> Election.chain_storage_nodes(node_list)
    |> P2P.nearest_nodes()
    |> Enum.filter(&Node.locally_available?/1)
    |> NodeDistribution.split_storage_nodes(nb_sub_lists, sample_size)
  end

  defp wrap_async_queries(
         previous_address,
         node_public_keys,
         _nodes_distribution = [
           prev_tx_nodes_split,
           unspent_outputs_nodes_split
         ]
       ) do
    prev_tx_task =
      Task.async(fn ->
        DataFetcher.fetch_previous_transaction(previous_address, prev_tx_nodes_split)
      end)

    utxo_task =
      Task.async(fn ->
        DataFetcher.fetch_unspent_outputs(previous_address, unspent_outputs_nodes_split)
      end)

    nodes_view_task = Task.async(fn -> DataFetcher.fetch_p2p_view(node_public_keys) end)

    {prev_tx, prev_tx_node_involved} =
      case Task.await(prev_tx_task) do
        {:ok, tx, node_involved} ->
          {tx, node_involved}

        {:error, :not_found} ->
          {nil, nil}

        {:error, :invalid_transaction} ->
          raise "Invalid previous transaction"
      end

    {:ok, utxos, utxo_node_involved} = Task.await(utxo_task)
    nodes_view = Task.await(nodes_view_task)

    involved_nodes =
      [prev_tx_node_involved, utxo_node_involved]
      |> Enum.filter(& &1)
      |> P2P.distinct_nodes()

    {prev_tx, utxos, nodes_view, involved_nodes}
  end

  defp aggregate_views(
         nodes_view,
         node_public_keys,
         chain_storage_node_public_keys,
         beacon_storage_node_public_keys
       ) do
    %{chain_nodes_view: chain_nodes_view, beacon_nodes_view: beacon_nodes_view} =
      ArchEthic.Utils.bitstring_to_integer_list(nodes_view)
      |> Enum.with_index()
      |> Enum.reduce(
        %{
          chain_nodes_view: Enum.to_list(1..length(chain_storage_node_public_keys)),
          beacon_nodes_view: Enum.to_list(1..length(beacon_storage_node_public_keys))
        },
        &reduce_nodes_view(
          &1,
          &2,
          node_public_keys,
          chain_storage_node_public_keys,
          beacon_storage_node_public_keys
        )
      )
      |> Map.update!(:chain_nodes_view, &:erlang.list_to_bitstring/1)
      |> Map.update!(:beacon_nodes_view, &:erlang.list_to_bitstring/1)

    {chain_nodes_view, beacon_nodes_view}
  end

  defp reduce_nodes_view(
         {availability, index},
         acc,
         node_public_keys,
         chain_storage_node_public_keys,
         beacon_storage_node_public_keys
       ) do
    node_public_key = Enum.at(node_public_keys, index)

    chain_index = Enum.find_index(chain_storage_node_public_keys, &(&1 == node_public_key))

    beacon_index = Enum.find_index(beacon_storage_node_public_keys, &(&1 == node_public_key))

    acc
    |> Map.update!(:chain_nodes_view, fn view ->
      case chain_index do
        nil ->
          view

        _ ->
          List.replace_at(view, index, <<availability::1>>)
      end
    end)
    |> Map.update!(:beacon_nodes_view, fn view ->
      case beacon_index do
        nil ->
          view

        _ ->
          List.replace_at(view, index, <<availability::1>>)
      end
    end)
  end
end
