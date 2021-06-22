defmodule ArchEthic.SelfRepair.Notifier do
  @moduledoc false

  use GenServer

  alias ArchEthic.Crypto

  alias ArchEthic.PubSub

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.ReplicateTransaction
  alias ArchEthic.P2P.Node

  alias ArchEthic.Replication

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction

  alias ArchEthic.Utils

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    PubSub.register_to_node_update()
    {:ok, []}
  end

  def handle_info(
        {:node_update, %Node{available?: true, authorized?: true, first_public_key: node_key}},
        state
      ) do
    current_node_public_key = Crypto.first_node_public_key()

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
        ) -- previous_storage_nodes

      with true <- Utils.key_in_node_list?(previous_storage_nodes, current_node_public_key),
           {:ok, tx} <- TransactionChain.get_transaction(address) do
        Task.async_stream(
          next_storage_nodes,
          fn node = %Node{first_public_key: node_key} ->
            roles = Replication.roles(tx, node_key)
            P2P.send_message(node, %ReplicateTransaction{transaction: tx, roles: roles})
          end,
          on_timeout: :kill_task,
          ordered: false
        )
        |> Stream.run()
      end
    end)
    |> Stream.run()
  end
end
