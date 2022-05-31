defmodule Archethic.Mining.TransactionContext do
  @moduledoc """
  Gathering of the necessary information for the transaction validation:
  - previous transaction
  - unspent outputs
  """

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias __MODULE__.DataFetcher
  alias __MODULE__.NodeDistribution

  alias Archethic.TaskSupervisor

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.Utils

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
          io_storage_nodes_public_keys :: list(Crypto.key())
        ) ::
          {Transaction.t(), list(UnspentOutput.t()), list(Node.t()), bitstring(), bitstring(),
           bitstring()}
  def get(
        previous_address,
        chain_storage_node_public_keys,
        beacon_storage_node_public_keys,
        io_storage_node_public_keys
      ) do
    [prev_tx_nodes_split, unspent_outputs_nodes_split] =
      previous_nodes_distribution(previous_address, 2, 3)

    node_public_keys =
      [
        chain_storage_node_public_keys,
        beacon_storage_node_public_keys,
        io_storage_node_public_keys
      ]
      |> List.flatten()
      |> Enum.uniq()

    prev_tx_task = request_previous_tx(previous_address, prev_tx_nodes_split)
    utxo_task = request_utxo(previous_address, unspent_outputs_nodes_split)
    nodes_view_task = request_nodes_view(node_public_keys)

    {prev_tx, prev_tx_node_involved} = await_previous_tx_request(prev_tx_task)

    {:ok, utxos, utxo_node_involved} = Task.await(utxo_task)
    nodes_view = Task.await(nodes_view_task)

    involved_nodes =
      [prev_tx_node_involved, utxo_node_involved]
      |> Enum.filter(& &1)
      |> P2P.distinct_nodes()

    %{
      chain_nodes_view: chain_storage_nodes_view,
      beacon_nodes_view: beacon_storage_nodes_view,
      io_nodes_view: io_storage_nodes_view
    } =
      aggregate_views(
        nodes_view,
        chain_storage_node_public_keys,
        beacon_storage_node_public_keys,
        io_storage_node_public_keys
      )

    {prev_tx, utxos, involved_nodes, chain_storage_nodes_view, beacon_storage_nodes_view,
     io_storage_nodes_view}
  end

  defp previous_nodes_distribution(previous_address, nb_sub_lists, sample_size) do
    node_list =
      P2P.unprioritize_node(P2P.authorized_and_available_nodes(), Crypto.first_node_public_key())

    previous_address
    |> Election.chain_storage_nodes(node_list)
    |> P2P.nearest_nodes()
    |> Enum.filter(&Node.locally_available?/1)
    |> NodeDistribution.split_storage_nodes(nb_sub_lists, sample_size)
  end

  defp request_previous_tx(previous_address, nodes) do
    Task.Supervisor.async(TaskSupervisor, fn ->
      DataFetcher.fetch_previous_transaction(previous_address, nodes)
    end)
  end

  defp await_previous_tx_request(task) do
    case Task.await(task) do
      {:ok, tx, node_involved} ->
        {tx, node_involved}

      {:error, :not_found} ->
        {nil, nil}

      {:error, :invalid_transaction} ->
        raise "Invalid previous transaction"
    end
  end

  defp request_utxo(previous_address, nodes) do
    TaskSupervisor
    |> Task.Supervisor.async(fn ->
      DataFetcher.fetch_unspent_outputs(previous_address, nodes)
    end)
  end

  defp request_nodes_view(node_public_keys) do
    TaskSupervisor
    |> Task.Supervisor.async(fn ->
      DataFetcher.fetch_p2p_view(node_public_keys)
    end)
  end

  defp aggregate_views(
         nodes_view,
         chain_storage_node_public_keys,
         beacon_storage_node_public_keys,
         io_storage_node_public_keys
       ) do
    nb_chain_storage_nodes = length(chain_storage_node_public_keys)
    nb_beacon_storage_nodes = length(beacon_storage_node_public_keys)
    nb_io_storage_nodes = length(io_storage_node_public_keys)

    acc = %{
      chain_nodes_view: <<0::size(nb_chain_storage_nodes)>>,
      beacon_nodes_view: <<0::size(nb_beacon_storage_nodes)>>,
      io_nodes_view: <<0::size(nb_io_storage_nodes)>>
    }

    Enum.reduce(nodes_view, acc, fn
      {node_public_key, true}, acc ->
        chain_index = Enum.find_index(chain_storage_node_public_keys, &(&1 == node_public_key))
        beacon_index = Enum.find_index(beacon_storage_node_public_keys, &(&1 == node_public_key))
        io_index = Enum.find_index(io_storage_node_public_keys, &(&1 == node_public_key))

        acc
        |> Map.update!(:chain_nodes_view, &set_node_view(&1, chain_index))
        |> Map.update!(:beacon_nodes_view, &set_node_view(&1, beacon_index))
        |> Map.update!(:io_nodes_view, &set_node_view(&1, io_index))

      {_node_public_key, false}, acc ->
        acc
    end)
  end

  defp set_node_view(view, nil), do: view
  defp set_node_view(view, index), do: Utils.set_bitstring_bit(view, index)
end
