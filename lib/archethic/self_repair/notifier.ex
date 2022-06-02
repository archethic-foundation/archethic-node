defmodule Archethic.SelfRepair.Notifier do
  @moduledoc false

  use GenServer

  #  alias Archethic.Crypto
  #
  #  alias Archethic.Election
  #
  alias Archethic.PubSub

  #  alias Archethic.P2P
  #  alias Archethic.P2P.Message.ReplicateTransactionChain
  alias Archethic.P2P.Node

  #  alias Archethic.TaskSupervisor
  #
  #  alias Archethic.TransactionChain
  #  alias Archethic.TransactionChain.Transaction
  #
  #  alias Archethic.Utils

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    PubSub.register_to_node_update()
    {:ok, []}
  end

  def handle_info(
        {:node_update, %Node{available?: true, authorized?: true, first_public_key: _node_key}},
        state
      ) do
    # FIXME
    # TODO: Leverage node update reason to know if we have to take the new node in consideration or to reject the nodes to replay election algorithm

    #   current_node_public_key = Crypto.first_node_public_key()

    #   if node_key == current_node_public_key do
    #     {:noreply, state}
    #   else
    #     node_list = P2P.list_nodes() |> Enum.reject(&(&1.first_public_key == node_key))

    #     node_key
    #     |> get_transactions_to_sync(node_list)
    #     |> forward_transactions(node_list, current_node_public_key)

    #     {:noreply, state}
    #   end
    {:noreply, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  # defp get_transactions_to_sync(node_public_key, node_list) do
  #   TransactionChain.list_all([:address, :type])
  #   |> Stream.map(fn %Transaction{address: address, type: type} ->
  #     {address, type, Election.chain_storage_nodes_with_type(address, type, node_list)}
  #   end)
  #   |> Stream.filter(fn {_address, _type, nodes} ->
  #     Utils.key_in_node_list?(nodes, node_public_key)
  #   end)
  # end

  # defp forward_transactions(
  #        transactions,
  #        node_list,
  #        current_node_public_key
  #      ) do
  #   transactions
  #   |> Stream.each(fn {address, type, _nodes} ->
  #     previous_storage_nodes =
  #       Election.chain_storage_nodes_with_type(
  #         address,
  #         type,
  #         node_list
  #       )

  #     next_storage_nodes =
  #       Election.chain_storage_nodes_with_type(
  #         address,
  #         type,
  #         P2P.available_nodes() -- previous_storage_nodes
  #       )

  #     with true <- Utils.key_in_node_list?(next_storage_nodes, current_node_public_key),
  #          {:ok, tx} <- TransactionChain.get_transaction(address) do
  #       Task.Supervisor.async_stream_nolink(
  #         TaskSupervisor,
  #         next_storage_nodes,
  #         &P2P.send_message(&1, %ReplicateTransactionChain{transaction: tx}),
  #         ordered: false,
  #         on_timeout: :kill_task
  #       )
  #       |> Stream.run()
  #     end
  #   end)
  #   |> Stream.run()
  # end
end
