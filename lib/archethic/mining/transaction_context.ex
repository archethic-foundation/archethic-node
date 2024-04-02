defmodule Archethic.Mining.TransactionContext do
  @moduledoc """
  Gathering of the necessary information for the transaction validation:
  - previous transaction
  - unspent outputs
  """

  alias Archethic.BeaconChain
  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Ping
  alias Archethic.P2P.Node

  alias Archethic.TaskSupervisor

  alias Archethic.TransactionChain
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
          previous_tx_address :: Crypto.prepended_hash(),
          genesis_address :: Crypto.prepended_hash(),
          chain_storage_node_public_keys :: list(Crypto.key()),
          beacon_storage_nodes_public_keys :: list(Crypto.key()),
          io_storage_nodes_public_keys :: list(Crypto.key())
        ) ::
          {Transaction.t(), list(UnspentOutput.t()), list(Node.t()), bitstring(), bitstring(),
           bitstring()}
  def get(
        previous_address,
        genesis_address,
        chain_storage_node_public_keys,
        beacon_storage_node_public_keys,
        io_storage_node_public_keys
      ) do
    authorized_nodes = P2P.authorized_and_available_nodes()

    node_public_keys =
      [
        chain_storage_node_public_keys,
        beacon_storage_node_public_keys,
        io_storage_node_public_keys
      ]
      |> List.flatten()
      |> Enum.uniq()

    prev_tx_task = request_previous_tx(previous_address, authorized_nodes)
    utxos_task = request_utxos(genesis_address, authorized_nodes)
    nodes_view_task = request_nodes_view(node_public_keys)

    [prev_tx, utxos, nodes_view] = Task.await_many([prev_tx_task, utxos_task, nodes_view_task])

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

    {prev_tx, utxos, [], chain_storage_nodes_view, beacon_storage_nodes_view,
     io_storage_nodes_view}
  end

  defp request_previous_tx(previous_address, authorized_nodes) do
    previous_storage_nodes = Election.chain_storage_nodes(previous_address, authorized_nodes)

    Task.Supervisor.async(
      TaskSupervisor,
      fn ->
        # Timeout of 4 sec because the coordinator node wait 5 sec to get the context
        # from the cross validation nodes
        case TransactionChain.fetch_transaction(previous_address, previous_storage_nodes,
               search_mode: :remote,
               timeout: 4000
             ) do
          {:ok, tx} ->
            tx

          {:error, _} ->
            nil
        end
      end
    )
  end

  defp request_utxos(genesis_address, authorized_nodes) do
    previous_summary_time = BeaconChain.previous_summary_time(DateTime.utc_now())

    genesis_nodes =
      genesis_address
      |> Election.chain_storage_nodes(authorized_nodes)
      |> Election.get_synchronized_nodes_before(previous_summary_time)

    Task.Supervisor.async(TaskSupervisor, fn ->
      genesis_address
      |> TransactionChain.fetch_unspent_outputs(genesis_nodes)
      |> Enum.to_list()
    end)
  end

  defp request_nodes_view(node_public_keys) do
    Task.Supervisor.async(TaskSupervisor, fn ->
      Task.Supervisor.async_stream_nolink(
        TaskSupervisor,
        node_public_keys,
        fn node_public_key ->
          {node_public_key, P2P.send_message(node_public_key, %Ping{}, timeout: 1000)}
        end,
        on_timeout: :kill_task
      )
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn
        {:ok, {node_public_key, {:ok, %Ok{}}}} -> {node_public_key, true}
        {:ok, {node_public_key, _}} -> {node_public_key, false}
      end)
      |> Enum.into(%{})
    end)
  end

  @doc """
  Set bitmap of the available nodes for each group of node

  ## Examples

      iex> TransactionContext.aggregate_views(
      ...>    %{
      ...>      "node1" => true,
      ...>      "node2" => false,
      ...>      "node3" => true,
      ...>      "node4" => true,
      ...>      "node5" => false
      ...>    },
      ...>    ["node1", "node2", "node3"],
      ...>    ["node4", "node2", "node5"],
      ...>    ["node2", "node3", "node1"]
      ...> )
      %{
        chain_nodes_view: <<1::1, 0::1, 1::1>>,
        beacon_nodes_view: <<1::1, 0::1, 0::1>>,
        io_nodes_view: <<0::1, 1::1, 1::1>>
      }
  """
  @spec aggregate_views(
          nodes_view :: list({public_key :: Crypto.key(), available? :: boolean()}),
          chain_storage_node_public_keys :: list(Crypto.key()),
          beacon_storage_node_public_keys :: list(Crypto.key()),
          io_storage_node_public_keys :: list(Crypto.key())
        ) :: %{
          chain_nodes_view: bitstring(),
          beacon_nodes_view: bitstring(),
          io_nodes_view: bitstring()
        }
  def aggregate_views(
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
