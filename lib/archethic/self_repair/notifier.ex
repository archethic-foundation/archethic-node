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

  alias Archethic.{
    BeaconChain,
    BeaconChain.SummaryAggregate,
    BeaconChain.SummaryTimer,
    Crypto,
    Election,
    PubSub,
    P2P,
    P2P.Node,
    TaskSupervisor,
    TransactionChain,
    Utils
  }

  alias Archethic.P2P.Message.{
    ReplicateTransaction
  }

  alias Archethic.TransactionChain.{Transaction, Transaction.ValidationStamp}

  require Logger

  @spec start_link(args :: any()) :: GenServer.on_start()
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  @spec init(any()) :: {:ok, %{notified: %{}}}
  def init(_) do
    PubSub.register_to_node_update()
    {:ok, %{notified: %{}}}
  end

  # authorized node becomes unavailable
  @spec handle_info(msg :: {:node_update, Node.t()} | any(), state :: map()) ::
          {:noreply, state :: map()}
  def(
    handle_info(
      {:node_update,
       %Node{
         available?: false,
         authorized?: true,
         first_public_key: node_key,
         authorization_date: authorization_date
       }},
      state = %{notified: notified}
    )
  ) do
    current_node_public_key = Crypto.first_node_public_key()
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    with :lt <- DateTime.compare(authorization_date, now),
         nil <- Map.get(notified, node_key),
         false <- current_node_public_key == node_key do
      repair_transactions(node_key, current_node_public_key)
      repair_beacon_summary_aggregates(node_key, current_node_public_key)

      {:noreply, Map.update!(state, :notified, &Map.put(&1, node_key, %{}))}
    else
      _ ->
        {:noreply, state}
    end
  end

  # authorized node becomes unauthorized
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
      repair_beacon_summary_aggregates(node_key, current_node_public_key)
      {:noreply, Map.update!(state, :notified, &Map.put(&1, node_key, %{}))}
    else
      _ ->
        {:noreply, state}
    end
  end

  # authorized node becomes available again
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

  @spec repair_beacon_summary_aggregates(
          unavailable_node_key :: Crypto.key(),
          current_node_public_key :: Crypto.key()
        ) :: :ok
  def repair_beacon_summary_aggregates(unavailable_node_key, current_node_public_key) do
    if P2P.authorized_node?(current_node_public_key) do
      Logger.debug("Trying to repair shard unavailablity due to a topology change",
        node: Base.encode16(unavailable_node_key)
      )

      Utils.genesis_node_enrollment_date()
      |> SummaryTimer.next_summaries()
      |> Stream.map(&summary_aggregates_to_sync(&1))
      |> Stream.filter(&Utils.key_in_node_list?(elem(&1, 1), unavailable_node_key))
      |> Stream.filter(&(&1 |> elem(1) != []))
      |> Stream.map(
        &sync_unavailable_summary_aggregate(&1, current_node_public_key, unavailable_node_key)
      )
      |> Stream.run()
    end

    :ok
  end

  @spec summary_aggregates_to_sync(summary_time :: DateTime.t()) ::
          {summary_time :: DateTime.t(), previous_chain_storage_nodes :: list(Node.t())}
  def summary_aggregates_to_sync(summary_time) do
    node_list =
      P2P.list_nodes()
      |> Enum.filter(fn node ->
        node.authorization_date != nil &&
          DateTime.compare(node.authorization_date, summary_time) == :lt
      end)

    previous_chain_storage_nodes =
      summary_time
      |> Crypto.derive_beacon_aggregate_address()
      |> Election.chain_storage_nodes(node_list)

    {summary_time, previous_chain_storage_nodes}
  end

  @spec sync_unavailable_summary_aggregate(
          {summary_time :: DateTime.t(), previous_chain_storage_nodes :: list(Node.t())},
          current_node_public_key :: Crypto.key(),
          unavailable_node_key :: Crypto.key()
        ) :: :ok
  def sync_unavailable_summary_aggregate(
        {summary_time, previous_chain_storage_nodes},
        current_node_public_key,
        unavailable_node_key
      ) do
    old_nodes_key = Enum.map(previous_chain_storage_nodes, & &1.first_public_key)

    new_chain_storage_nodes =
      Election.chain_storage_nodes(
        Crypto.derive_beacon_aggregate_address(summary_time),
        P2P.authorized_nodes()
        |> Enum.reject(&(&1.first_public_key == unavailable_node_key))
      )
      |> Enum.reject(&(&1.first_public_key in old_nodes_key))

    with {:empty, false} <- {:empty, Enum.empty?(new_chain_storage_nodes)},
         #  current node should not be part of previous_chain_storage_nodes as it would already have aggregate
         {:prev_election, false} <-
           {:prev_election,
            Utils.key_in_node_list?(previous_chain_storage_nodes, current_node_public_key)},
         # current node should be part of new_chain storage nodes to do the pull
         {:new_election, true} <-
           {:new_election,
            Utils.key_in_node_list?(new_chain_storage_nodes, current_node_public_key)},
         # filter out unavailable nodes from prev strage nodes to fetch aggregate
         storage_nodes when storage_nodes != [] <-
           Enum.filter(previous_chain_storage_nodes, &(&1.available? == true)),
         #  quorum read for aggregate fetching
         {:ok, aggregate = %SummaryAggregate{}} <-
           BeaconChain.fetch_summaries_aggregate_from_nodes(summary_time, storage_nodes) do
      # Pull mechnism to fetch summary aggreagete from local calulation os shards
      BeaconChain.write_summaries_aggregate(aggregate)

      Logger.debug(
        "Fetched and Stored Missing #{summary_time} Aggregate due to shard unavailablity",
        Repair: "SelfRepair.Notifier"
      )

      :ok
    else
      {:empty, true} ->
        Logger.debug("AggregateRepair: #{summary_time} : omitted ",
          reason: "List of New Storage Nodes is empty."
        )

      {:prev_election, true} ->
        Logger.debug("AggregateRepair: #{summary_time} : omitted ",
          reason: "Current Node is already a member of the Previous Chain Storage Nodes."
        )

      {:new_election, false} ->
        Logger.debug("AggregateRepair: #{summary_time} : omitted",
          reason: "The current node is not a part of the New Shard Selection/New Election."
        )

      [] ->
        Logger.warning("AggregateRepair: #{summary_time} : omitted",
          reason: "Previous Storage Nodes are not available"
        )

      {:error, e} ->
        Logger.warning("AggregateRepair: #{summary_time} : AggregateFetchError #{e}")

      e ->
        Logger.warning("AggregateRepair: #{summary_time} : Unhandled Error #{e}")

        :ok
    end
  end

  def repair_transactions(node_key, current_node_public_key) do
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
