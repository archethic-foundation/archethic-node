defmodule Uniris.SelfRepair.Notifier do
  @moduledoc false

  use GenServer

  alias Uniris.Crypto

  alias Uniris.PubSub

  alias Uniris.P2P
  alias Uniris.P2P.Message.ReplicateTransaction
  alias Uniris.P2P.Node

  alias Uniris.Replication

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction

  alias Uniris.Utils

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    PubSub.register_to_node_update()
    {:ok, []}
  end

  def handle_info(
        {:node_update,
         %Node{available?: true, authorized?: true, first_public_key: node_key}},
        state
      ) do
    current_node_public_key = Crypto.node_public_key(0)

    if node_key == current_node_public_key do
      {:noreply, state}
    else
      node_list = P2P.authorized_nodes() |> Enum.reject(&(&1.first_public_key == node_key))

      node_key
      |> get_transactions_to_sync(node_list)
      |> forward_transactions(node_list, current_node_public_key)

      {:noreply, state}
    end
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  defp get_transactions_to_sync(node_public_key, node_list) do
    TransactionChain.list_all([:address, :type])
    |> Stream.map(fn %Transaction{address: address, type: type} ->
      {address, type, Replication.chain_storage_nodes_with_type(address, type, node_list)}
    end)
    |> Stream.filter(fn {address, type, nodes} ->
      Replication.chain_storage_node?(
        address,
        type,
        node_public_key,
        nodes
      )
    end)
  end

  defp forward_transactions(
         transactions,
         node_list,
         current_node_public_key
       ) do
    transactions
    |> Stream.each(fn {address, type, _nodes} ->
      previous_storage_nodes =
        Replication.chain_storage_nodes_with_type(
          address,
          type,
          node_list
        )

      next_storage_nodes =
        Replication.chain_storage_nodes_with_type(
          address,
          type
        )

      with true <- Utils.key_in_node_list?(previous_storage_nodes, current_node_public_key),
           {:ok, tx} <- TransactionChain.get_transaction(address) do
        # TODO: improve to request if the node has the transaction already
        P2P.broadcast_message(next_storage_nodes, %ReplicateTransaction{transaction: tx})
      end
    end)
    |> Stream.run()
  end
end
