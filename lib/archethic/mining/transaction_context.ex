defmodule Archethic.Mining.TransactionContext do
  @moduledoc """
  Gathering of the necessary information for the transaction validation:
  - previous transaction
  - unspent outputs
  """

  alias Archethic.BeaconChain

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Ping
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.Utils

  require Logger

  @doc """
  Request concurrently the context of the transaction including the previous transaction,
  the unspent outputs, genesis address and P2P view for the storage nodes and validation nodes
  as long as the involved nodes for the retrieval
  """
  @spec get(
          transaction :: Transaction.t(),
          validation_time :: DateTime.t(),
          authorized_nodes :: list(Node.t())
        ) :: Keyword.t()
  def get(tx, validation_time, authorized_nodes) do
    resolved_addresses_task =
      Task.async(fn -> TransactionChain.resolve_transaction_addresses!(tx) end)

    previous_address = Transaction.previous_address(tx)
    previous_tx = request_previous_tx(previous_address, authorized_nodes)

    genesis_address =
      case previous_tx do
        %Transaction{validation_stamp: %ValidationStamp{genesis_address: genesis_address}} ->
          genesis_address

        nil ->
          previous_address
      end

    utxos_task = request_utxos(genesis_address, authorized_nodes)

    resolved_addresses = Task.await(resolved_addresses_task)

    {chain_storage_nodes, beacon_storage_nodes, io_nodes} =
      get_involved_nodes(
        tx,
        genesis_address,
        resolved_addresses,
        validation_time,
        authorized_nodes
      )

    view_nodes =
      Enum.concat([chain_storage_nodes, beacon_storage_nodes, io_nodes]) |> P2P.distinct_nodes()

    nodes_view = request_nodes_view(view_nodes)

    %{
      chain_nodes_view: chain_storage_nodes_view,
      beacon_nodes_view: beacon_storage_nodes_view,
      io_nodes_view: io_storage_nodes_view
    } = aggregate_views(nodes_view, chain_storage_nodes, beacon_storage_nodes, io_nodes)

    utxos = Task.await(utxos_task)

    [
      chain_storage_nodes: chain_storage_nodes,
      beacon_storage_nodes: beacon_storage_nodes,
      io_storage_nodes: io_nodes,
      resolved_addresses: resolved_addresses,
      genesis_address: genesis_address,
      previous_transaction: previous_tx,
      unspent_outputs: utxos,
      chain_storage_nodes_view: chain_storage_nodes_view,
      beacon_storage_nodes_view: beacon_storage_nodes_view,
      io_storage_nodes_view: io_storage_nodes_view
    ]
  end

  defp request_previous_tx(previous_address, authorized_nodes) do
    previous_storage_nodes = Election.chain_storage_nodes(previous_address, authorized_nodes)

    # Timeout of 4 sec because the coordinator node wait 5 sec to get the context
    # from the cross validation nodes
    case TransactionChain.fetch_transaction(previous_address, previous_storage_nodes,
           timeout: 4000
         ) do
      {:ok, tx} -> tx
      {:error, _} -> nil
    end
  end

  defp request_utxos(genesis_address, authorized_nodes) do
    previous_summary_time = BeaconChain.previous_summary_time(DateTime.utc_now())

    genesis_nodes =
      genesis_address
      |> Election.chain_storage_nodes(authorized_nodes)
      |> Election.get_synchronized_nodes_before(previous_summary_time)

    Task.Supervisor.async(Archethic.task_supervisors(), fn ->
      genesis_address
      |> TransactionChain.fetch_unspent_outputs(genesis_nodes)
      |> Enum.to_list()
    end)
  end

  defp get_involved_nodes(
         %Transaction{address: address, type: type},
         genesis_address,
         resolved_addresses,
         validation_time,
         authorized_nodes
       ) do
    chain_storage_nodes = Election.chain_storage_nodes(address, authorized_nodes)
    genesis_storage_nodes = Election.chain_storage_nodes(genesis_address, authorized_nodes)

    beacon_storage_nodes =
      address
      |> BeaconChain.subset_from_address()
      |> Election.beacon_storage_nodes(BeaconChain.next_slot(validation_time), authorized_nodes)

    io_storage_nodes =
      if Transaction.network_type?(type) do
        P2P.list_nodes()
      else
        resolved_addresses
        |> Map.values()
        |> Election.io_storage_nodes(authorized_nodes)
      end

    io_nodes = io_storage_nodes |> Enum.concat(genesis_storage_nodes) |> P2P.distinct_nodes()

    {chain_storage_nodes, beacon_storage_nodes, io_nodes}
  end

  defp request_nodes_view(nodes) do
    Task.Supervisor.async_stream_nolink(
      Archethic.task_supervisors(),
      nodes,
      &{&1.first_public_key, P2P.send_message(&1, %Ping{}, 1000)},
      on_timeout: :kill_task
    )
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn
      {:ok, {node_public_key, {:ok, %Ok{}}}} -> {node_public_key, true}
      {:ok, {node_public_key, _}} -> {node_public_key, false}
    end)
    |> Enum.into(%{})
  end

  defp aggregate_views(nodes_view, chain_storage_nodes, beacon_storage_nodes, io_nodes) do
    nb_chain_storage_nodes = length(chain_storage_nodes)
    nb_beacon_storage_nodes = length(beacon_storage_nodes)
    nb_io_nodes = length(io_nodes)

    acc = %{
      chain_nodes_view: <<0::size(nb_chain_storage_nodes)>>,
      beacon_nodes_view: <<0::size(nb_beacon_storage_nodes)>>,
      io_nodes_view: <<0::size(nb_io_nodes)>>
    }

    Enum.reduce(nodes_view, acc, fn
      {node_public_key, true}, acc ->
        chain_index =
          Enum.find_index(chain_storage_nodes, &(&1.first_public_key == node_public_key))

        beacon_index =
          Enum.find_index(beacon_storage_nodes, &(&1.first_public_key == node_public_key))

        io_index = Enum.find_index(io_nodes, &(&1.first_public_key == node_public_key))

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
