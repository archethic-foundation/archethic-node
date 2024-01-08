defmodule Archethic.Reward.Scheduler do
  @moduledoc false

  use GenStateMachine, callback_mode: [:handle_event_function]
  @vsn 1

  alias Archethic

  alias Archethic.{Crypto, PubSub, DB, P2P, P2P.Node}
  alias Archethic.{Reward, Election, Utils, Utils.DetectNodeResponsiveness}

  require Logger

  @spec start_link(list(), any) :: GenStateMachine.on_start()
  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenStateMachine.start_link(__MODULE__, args, opts)
  end

  def init(args) do
    interval = Keyword.fetch!(args, :interval)
    state_data = Map.put(%{}, :interval, interval)
    # Set trap_exit globally for the process
    Process.flag(:trap_exit, true)

    if Archethic.up?() do
      {state, new_state_data, events} = start_scheduler(state_data)
      {:ok, state, new_state_data, events}
    else
      Logger.info(" Reward Scheduler: Waiting for Node to complete Bootstrap. ")

      PubSub.register_to_node_status()
      {:ok, :idle, state_data}
    end
  end

  @doc """
    Computers start parameters for the scheduler
  """
  def start_scheduler(state_data) do
    Logger.info("Reward Scheduler: Starting... ")

    PubSub.register_to_node_update()

    case Crypto.first_node_public_key() |> P2P.get_node_info() |> elem(1) do
      %Node{authorized?: true, available?: true} ->
        PubSub.register_to_new_transaction_by_type(:mint_rewards)
        PubSub.register_to_new_transaction_by_type(:node_rewards)

        index = Crypto.number_of_network_pool_keys()
        Logger.info("Reward Scheduler scheduled during init - (index: #{index})")

        {:idle,
         state_data
         |> Map.put(:index, index)
         |> Map.put(:next_address, Reward.next_address(index)),
         {:next_event, :internal, :schedule}}

      _ ->
        Logger.info("Reward Scheduler waiting for Node Update Message")

        {:idle, state_data, []}
    end
  end

  def handle_event(:info, :node_up, _, state_data) do
    # Node is up start Scheduler
    {:idle, new_state_data, events} = start_scheduler(state_data)
    {:keep_state, new_state_data, events}
  end

  def handle_event(:info, :node_down, _, %{interval: interval, timer: timer}) do
    # Node is down stop Scheduler
    Process.cancel_timer(timer)
    {:next_state, :idle, %{interval: interval}}
  end

  def handle_event(:info, :node_down, _, %{interval: interval}) do
    # Node is down stop Scheduler
    {:next_state, :idle, %{interval: interval}}
  end

  def handle_event(
        :info,
        {:node_update,
         %Node{authorized?: true, available?: true, first_public_key: first_public_key}},
        :idle,
        data
      ) do
    if Crypto.first_node_public_key() == first_public_key do
      index = Crypto.number_of_network_pool_keys()

      PubSub.register_to_new_transaction_by_type(:mint_rewards)
      PubSub.register_to_new_transaction_by_type(:node_rewards)

      Logger.info("Start the network pool reward scheduler - (index: #{index})")

      new_data =
        data
        |> Map.put(:index, index)
        |> Map.put(:next_address, Reward.next_address(index))

      {:keep_state, new_data, {:next_event, :internal, :schedule}}
    else
      :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        {:node_update, %Node{authorized?: false, first_public_key: first_public_key}},
        state,
        data
      )
      when state != :idle do
    if Crypto.first_node_public_key() == first_public_key do
      case Map.pop(data, :timer) do
        {nil, _} ->
          {:next_state, :idle, data}

        {timer, new_data} ->
          Process.cancel_timer(timer)
          {:next_state, :idle, new_data}
      end
    else
      :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        {:node_update, %Node{available?: false, first_public_key: first_public_key}},
        _state,
        data
      ) do
    if Crypto.first_node_public_key() == first_public_key do
      case Map.pop(data, :timer) do
        {nil, _} ->
          {:next_state, :idle, data}

        {timer, new_data} ->
          Process.cancel_timer(timer)
          {:next_state, :idle, new_data}
      end
    else
      :keep_state_and_data
    end
  end

  def handle_event(:info, {:node_update, _}, _state, _data), do: :keep_state_and_data

  def handle_event(:info, :mint_rewards, :scheduled, data) do
    {:next_state, :triggered, data, {:next_event, :internal, :make_rewards}}
  end

  def handle_event(
        :info,
        {:new_transaction, _address, :mint_rewards, _timestamp},
        :triggered,
        data = %{index: index}
      ) do
    next_index = index + 1
    next_address = Reward.next_address(next_index)

    new_data =
      data
      |> Map.put(:index, next_index)
      |> Map.put(:next_address, next_address)

    new_data =
      case Map.pop(new_data, :watcher) do
        {nil, data} ->
          data

        {pid, data} ->
          Process.exit(pid, :kill)
          data
      end

    validation_nodes = Election.storage_nodes(next_address, P2P.authorized_and_available_nodes())

    if trigger_node?(validation_nodes) do
      Logger.debug("Initialize node rewards tx after mint rewards")
      send_node_rewards(next_index)
      {:keep_state, new_data}
    else
      Logger.debug("Start node responsivness for node rewards tx after mint rewards replication")

      {:ok, pid} =
        DetectNodeResponsiveness.start_link(next_address, length(validation_nodes), fn count ->
          if trigger_node?(validation_nodes, count) do
            Logger.debug("Node reward creation...attempt #{count}",
              transaction_address: Base.encode16(next_address)
            )

            send_node_rewards(next_index)
          end
        end)

      {:keep_state, Map.put(new_data, :watcher, pid)}
    end
  end

  def handle_event(
        :info,
        {:new_transaction, address, :mint_rewards, _timestamp},
        :scheduled,
        data = %{next_address: next_address, index: index}
      ) do
    Logger.debug(
      "Reschedule rewards after reception of mint rewards transaction in scheduled state instead of triggered state"
    )

    # We prevent non scheduled transactions to change
    next_index =
      if next_address == address do
        index + 1
      else
        index
      end

    next_address = Reward.next_address(next_index)

    new_data =
      data
      |> Map.put(:index, next_index)
      |> Map.put(:next_address, next_address)

    validation_nodes = Election.storage_nodes(next_address, P2P.authorized_and_available_nodes())

    if trigger_node?(validation_nodes) do
      Logger.debug("Initialize node rewards tx after mint rewards")
      send_node_rewards(next_index)
      {:next_state, :triggered, new_data}
    else
      Logger.debug("Start node responsivness for node rewards tx after mint rewards replication")

      {:ok, pid} =
        DetectNodeResponsiveness.start_link(next_address, length(validation_nodes), fn count ->
          if trigger_node?(validation_nodes, count) do
            Logger.debug("Node reward creation...attempt #{count}",
              transaction_address: Base.encode16(next_address)
            )

            send_node_rewards(next_index)
          end
        end)

      {:next_state, :triggered, Map.put(new_data, :watcher, pid)}
    end
  end

  def handle_event(
        :info,
        {:new_transaction, address, :node_rewards, _timestamp},
        :triggered,
        data = %{next_address: next_address}
      )
      when next_address == address do
    new_data =
      case Map.pop(data, :watcher) do
        {nil, data} ->
          data

        {pid, data} ->
          Process.exit(pid, :kill)
          data
      end

    new_data = Map.update!(new_data, :index, &(&1 + 1))

    Logger.debug("Reschedule after node reward replication")

    {:keep_state, new_data, {:next_event, :internal, :schedule}}
  end

  def handle_event(
        :info,
        {:new_transaction, address, :node_rewards, _timestamp},
        :scheduled,
        data = %{next_address: next_address}
      ) do
    Logger.debug(
      "Reschedule rewards after reception of node rewards transaction in scheduled state instead of triggered state"
    )

    # We prevent non scheduled transactions to change
    new_data =
      if next_address == address do
        Map.update!(data, :index, &(&1 + 1))
      else
        data
      end

    {:keep_state, new_data, {:next_event, :internal, :schedule}}
  end

  def handle_event(
        :info,
        {:EXIT, pid, {:shutdown, :hard_timeout}},
        :triggered,
        data = %{watcher: watcher_pid}
      )
      when watcher_pid == pid do
    {:keep_state, Map.delete(data, :watcher), {:next_event, :internal, :schedule}}
  end

  def handle_event(
        :info,
        {:EXIT, pid, _},
        _state,
        data = %{watcher: watcher_pid}
      )
      when watcher_pid == pid do
    {:keep_state, Map.delete(data, :watcher)}
  end

  def handle_event(
        :info,
        {:EXIT, _pid, _},
        _state,
        _data
      ) do
    :keep_state_and_data
  end

  def handle_event(
        :internal,
        :make_rewards,
        :triggered,
        data = %{index: index, next_address: tx_address}
      ) do
    validation_nodes = Election.storage_nodes(tx_address, P2P.authorized_and_available_nodes())

    if trigger_node?(validation_nodes) do
      mint_node_rewards(index)
      :keep_state_and_data
    else
      {:ok, pid} =
        DetectNodeResponsiveness.start_link(tx_address, length(validation_nodes), fn count ->
          if trigger_node?(validation_nodes, count) do
            Logger.debug("Mint reward creation...attempt #{count}",
              transaction_address: Base.encode16(tx_address)
            )

            mint_node_rewards(index)
          end
        end)

      {:keep_state, Map.put(data, :watcher, pid)}
    end
  end

  def handle_event(:internal, :schedule, _state, data = %{interval: interval, index: index}) do
    timer =
      case Map.get(data, :timer) do
        nil ->
          schedule(interval)

        timer ->
          Process.cancel_timer(timer)
          schedule(interval)
      end

    Logger.info(
      "Node rewards will be emitted in #{Utils.remaining_seconds_from_timer(timer)} seconds"
    )

    new_data =
      data
      |> Map.put(:timer, timer)
      |> Map.put(:next_address, Reward.next_address(index))

    {:next_state, :scheduled, new_data}
  end

  def handle_event(:cast, {:new_conf, conf}, _, data) do
    case Keyword.get(conf, :interval) do
      nil ->
        :keep_state_and_data

      new_interval ->
        {:noreply, Map.put(data, :interval, new_interval)}
    end
  end

  def handle_event(:info, _, :idle, _state), do: :keep_state_and_data

  defp mint_node_rewards(index) do
    case DB.get_latest_burned_fees() do
      0 ->
        Logger.info("No mint rewards transaction needed")
        send_node_rewards(index)

      amount ->
        tx = Reward.new_rewards_mint(amount, index)

        Logger.info("New mint rewards transaction sent with #{amount} token",
          transaction_address: Base.encode16(tx.address)
        )

        Archethic.send_new_transaction(tx)
    end
  end

  defp send_node_rewards(index) do
    node_reward_tx = Reward.new_node_rewards(index)

    Archethic.send_new_transaction(node_reward_tx)
  end

  defp schedule(interval) do
    Process.send_after(self(), :mint_rewards, Utils.time_offset(interval))
  end

  defp trigger_node?(validation_nodes, count \\ 0) do
    %Node{first_public_key: initiator_key} = validation_nodes |> Enum.at(count)
    initiator_key == Crypto.first_node_public_key()
  end

  def config_change(nil), do: :ok

  def config_change(conf) do
    GenStateMachine.cast(__MODULE__, {:new_conf, conf})
  end

  def code_change(_old_vsn, state, data, _extra), do: {:ok, state, data}
end
