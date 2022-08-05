defmodule Archethic.SelfRepair.Notifier do
  @moduledoc """
  Process to handle repair in case of topology change by trying to replicate transactions to new shard composition.

  When a node receive a topology change due to the unavailability of a node,
  we compute the new election for the already stored transactions.

  Hence, a new shard might me formed as we notify the new transactions to the
  new storage nodes

  ```mermaid
  flowchart TD
      A[Node 4] --x|Topology change notification| B[Node1]
      B --> | List transactions| B
      B -->|Elect new nodes| H[Transaction replication]
      H -->|Replicate Transaction| C[Node2]
      H -->|Replicate Transaction| D[Node3]
  ```

  """

  use GenServer

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.PubSub

  alias Archethic.P2P
  alias Archethic.P2P.Message.ReplicateTransaction
  alias Archethic.P2P.Node

  alias Archethic.TaskSupervisor

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.Utils

  require Logger

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    PubSub.register_to_node_update()
    {:ok, %{notified: %{}}}
  end

  def handle_info(
        {:node_update,
         %Node{
           available?: false,
           authorized?: true,
           first_public_key: node_key,
           authorization_date: authorization_date
         }},
        state = %{notified: notified}
      ) do
    current_node_public_key = Crypto.first_node_public_key()
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    with :lt <- DateTime.compare(authorization_date, now),
         nil <- Map.get(notified, node_key),
         false <- current_node_public_key == node_key do
      repair_transactions(node_key, current_node_public_key)
      {:noreply, Map.update!(state, :notified, &Map.put(&1, node_key, %{}))}
    else
      _ ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:node_update,
         %Node{authorized?: false, authorization_date: date, first_public_key: node_key}},
        state = %{notified: notified}
      )
      when date != nil do
    current_node_public_key = Crypto.first_node_public_key()

    with nil <- Map.get(notified, node_key),
         false <- current_node_public_key == node_key do
      repair_transactions(node_key, current_node_public_key)
      {:noreply, Map.update!(state, :notified, &Map.put(&1, node_key, %{}))}
    else
      _ ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:node_update,
         %Node{available?: true, first_public_key: node_key, authorization_date: date}},
        state
      )
      when date != nil do
    {:noreply, Map.update!(state, :notified, &Map.delete(&1, node_key))}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  defp repair_transactions(node_key, current_node_public_key) do
    Logger.debug("Trying to repair transactions due to a topology change",
      node: Base.encode16(node_key)
    )

    node_key
    |> get_transactions_to_sync()
    |> Stream.each(&forward_transaction(&1, current_node_public_key))
    |> Stream.run()
  end

  defp get_transactions_to_sync(node_public_key) do
    # We fetch all the transactions existing and check if the disconnecting node was a storage node
    TransactionChain.list_all([:address, :type, validation_stamp: [:timestamp]])
    |> Stream.map(
      fn tx = %Transaction{
           address: address,
           type: type,
           validation_stamp: %ValidationStamp{timestamp: timestamp}
         } ->
        node_list =
          Enum.filter(
            P2P.list_nodes(),
            &(&1.authorization_date != nil and
                DateTime.compare(&1.authorization_date, timestamp) == :lt)
          )

        {tx, Election.chain_storage_nodes_with_type(address, type, node_list)}
      end
    )
    |> Stream.filter(fn {_tx, nodes} ->
      Utils.key_in_node_list?(nodes, node_public_key)
    end)
  end

  defp forward_transaction(
         {tx = %Transaction{address: address, type: type}, previous_storage_nodes},
         current_node_public_key
       ) do
    # We compute the new storage nodes minus the previous ones
    new_storage_nodes =
      Election.chain_storage_nodes_with_type(
        address,
        type,
        P2P.authorized_nodes() -- previous_storage_nodes
      )

    with false <- Enum.empty?(new_storage_nodes),
         true <- Utils.key_in_node_list?(previous_storage_nodes, current_node_public_key) do
      Logger.info("Repair started due to network topology change",
        transaction_address: Base.encode16(address),
        transaction_type: type
      )

      Task.Supervisor.async_stream_nolink(
        TaskSupervisor,
        new_storage_nodes,
        &P2P.send_message(&1, %ReplicateTransaction{transaction: tx}),
        ordered: false,
        on_timeout: :kill_task
      )
      |> Stream.run()
    end
  end
end
