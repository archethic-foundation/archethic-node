defmodule Archethic.Reward.Scheduler do
  @moduledoc false

  use GenStateMachine, callback_mode: [:handle_event_function]

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  alias Archethic.Crypto

  alias Archethic.PubSub

  alias Archethic.DB

  alias Archethic.P2P.Node

  alias Archethic.P2P

  alias Archethic.Reward

  alias Archethic.Utils
  alias Archethic.Utils.DetectNodeResponsiveness

  require Logger

  def start_link(args \\ []) do
    GenStateMachine.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc """
  Get the last node rewards scheduling date
  """
  @spec last_date() :: DateTime.t()
  def last_date do
    GenStateMachine.call(__MODULE__, :last_date)
  end

  def init(args) do
    interval = Keyword.fetch!(args, :interval)
    PubSub.register_to_node_update()
    Logger.info("Starting Reward Scheduler")

    case Crypto.first_node_public_key() |> P2P.get_node_info() |> elem(1) do
      %Node{authorized?: true, available?: true} ->
        Logger.info("Reward Scheduler scheduled during init")
        PubSub.register_to_new_transaction_by_type(:mint_rewards)
        PubSub.register_to_new_transaction_by_type(:node_rewards)

        index = Crypto.number_of_network_pool_keys()
        {:ok, :idle, %{interval: interval, index: index}, {:next_event, :internal, :schedule}}

      _ ->
        Logger.info("Reward Scheduler waitng for Node Update Message")

        {:ok, :idle, %{interval: interval}}
    end

    {:ok, :idle, %{interval: interval}}
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

      Logger.info("Start the network pool reward scheduler")
      {:keep_state, Map.put(data, :index, index), {:next_event, :internal, :schedule}}
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
        data
      ) do
    new_data = %{index: index} = Map.update!(data, :index, &(&1 + 1))
    send_node_rewards(index)
    {:keep_state, new_data}
  end

  def handle_event(
        :info,
        {:new_transaction, _address, :mint_rewards, _timestamp},
        :scheduled,
        data
      ) do
    Logger.debug(
      "Reschedule rewards after reception of mint rewards transaction in scheduled state instead of triggered state"
    )

    new_data = Map.update!(data, :index, &(&1 + 1))
    {:keep_state, new_data, {:next_event, :internal, :schedule}}
  end

  def handle_event(
        :info,
        {:new_transaction, _address, :node_rewards, _timestamp},
        :triggered,
        data
      ) do
    case Map.get(data, :watcher) do
      nil ->
        :ignore

      pid ->
        Process.exit(pid, :normal)
    end

    {:keep_state, Map.update!(data, :index, &(&1 + 1)), {:next_event, :internal, :schedule}}
  end

  def handle_event(
        :info,
        {:new_transaction, _address, :node_rewards, _timestamp},
        :scheduled,
        data
      ) do
    Logger.debug(
      "Reschedule rewards after reception of node rewards transaction in scheduled state instead of triggered state"
    )

    {:keep_state, Map.update!(data, :index, &(&1 + 1)), {:next_event, :internal, :schedule}}
  end

  def handle_event(
        :info,
        {:DOWN, _ref, :process, pid, _},
        :triggered,
        data = %{watcher: watcher_pid}
      )
      when watcher_pid == pid do
    {:keep_state, Map.delete(data, :watcher), {:next_event, :internal, :schedule}}
  end

  def handle_event(
        :info,
        {:DOWN, _ref, :process, pid, _},
        :scheduled,
        data = %{watcher: watcher_pid}
      )
      when pid == watcher_pid do
    {:keep_state, Map.delete(data, :watcher)}
  end

  def handle_event(:internal, :make_rewards, :triggered, data = %{index: index}) do
    tx_address = Reward.next_address(index)

    if Reward.initiator?(tx_address) do
      mint_node_rewards(index)
      :keep_state_and_data
    else
      {:ok, pid} =
        DetectNodeResponsiveness.start_link(tx_address, fn count ->
          if Reward.initiator?(tx_address, count) do
            Logger.debug("Mint reward creation...attempt #{count}",
              transaction_address: Base.encode16(tx_address)
            )

            mint_node_rewards(index)
          end
        end)

      Process.monitor(pid)

      {:keep_state, Map.put(data, :watcher, pid)}
    end
  end

  def handle_event(:internal, :schedule, _state, data = %{interval: interval}) do
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

    new_data = Map.put(data, :timer, timer)
    {:next_state, :scheduled, new_data}
  end

  def handle_event({:call, from}, :last_date, _state, _data = %{interval: interval}) do
    {:keep_state_and_data, {:reply, from, get_last_date(interval)}}
  end

  def handle_event(:cast, {:new_conf, conf}, _, data) do
    case Keyword.get(conf, :interval) do
      nil ->
        :keep_state_and_data

      new_interval ->
        {:noreply, Map.put(data, :interval, new_interval)}
    end
  end

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

  defp get_last_date(interval) do
    cron_expression = CronParser.parse!(interval, true)

    case DateTime.utc_now() do
      %DateTime{microsecond: {0, 0}} ->
        cron_expression
        |> CronScheduler.get_next_run_dates(DateTime.utc_now() |> DateTime.to_naive())
        |> Enum.at(1)
        |> DateTime.from_naive!("Etc/UTC")

      _ ->
        cron_expression
        |> CronScheduler.get_previous_run_date!(DateTime.utc_now() |> DateTime.to_naive())
        |> DateTime.from_naive!("Etc/UTC")
    end
  end

  defp schedule(interval) do
    Process.send_after(self(), :mint_rewards, Utils.time_offset(interval) * 1000)
  end

  def config_change(nil), do: :ok

  def config_change(conf) do
    GenStateMachine.cast(__MODULE__, {:new_conf, conf})
  end
end
