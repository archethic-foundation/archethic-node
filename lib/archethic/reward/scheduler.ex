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

        {:ok, :idle, %{interval: interval}, {:next_event, :internal, :schedule}}

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
        _data
      ) do
    if Crypto.first_node_public_key() == first_public_key do
      Logger.info("Start the network pool reward scheduler")
      {:keep_state_and_data, {:next_event, :internal, :schedule}}
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
      data
      |> Map.get(:timer, make_ref())
      |> Process.cancel_timer()

      {:next_state, :idle, Map.delete(state, :timer)}
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
      data
      |> Map.get(:timer, make_ref())
      |> Process.cancel_timer()

      {:next_state, :idle, Map.delete(data, :timer)}
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
        {:new_transaction, address, :mint_rewards, _timestamp},
        :triggered,
        _data
      ) do
    PubSub.unregister_to_new_transaction_by_address(address)

    send_node_rewards()
    :keep_state_and_data
  end

  def handle_event(
        :info,
        {:new_transaction, address, :node_rewards, _timestamp},
        :triggered,
        data
      ) do
    PubSub.unregister_to_new_transaction_by_address(address)

    case Map.get(data, :watcher) do
      nil ->
        :ignore

      pid ->
        Process.exit(pid, :normal)
    end

    {:keep_state, data, {:next_event, :internal, :schedule}}
  end

  def handle_event(
        :info,
        {:DOWN, _ref, :process, pid, _},
        :triggered,
        data = %{watcher: {address, watcher_pid}}
      )
      when watcher_pid == pid do
    PubSub.unregister_to_new_transaction_by_address(address)
    {:keep_state, Map.delete(data, :watcher), {:next_event, :internal, :schedule}}
  end

  def handle_event(
        :info,
        {:DOWN, _ref, :process, pid, _},
        :scheduled,
        data = %{watcher: {address, watcher_pid}}
      )
      when pid == watcher_pid do
    PubSub.unregister_to_new_transaction_by_address(address)
    {:keep_state, Map.delete(data, :watcher)}
  end

  def handle_event(:internal, :make_rewards, :triggered, data) do
    tx_address = Reward.next_address()

    if Reward.initiator?(tx_address) do
      mint_node_rewards()
      :keep_state_and_data
    else
      {:ok, pid} =
        DetectNodeResponsiveness.start_link(tx_address, fn count ->
          if Reward.initiator?(tx_address, count) do
            Logger.debug("Mint reward creation...attempt #{count}",
              transaction_address: Base.encode16(tx_address)
            )

            mint_node_rewards()
          end
        end)

      Process.monitor(pid)

      {:keep_state, Map.put(data, :watcher, {tx_address, pid})}
    end
  end

  def handle_event(:internal, :schedule, _state, data = %{interval: interval}) do
    timer = schedule(interval)
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

  defp mint_node_rewards do
    case DB.get_latest_burned_fees() do
      0 ->
        Logger.info("No mint rewards transaction needed")
        send_node_rewards()

      amount ->
        tx = Reward.new_rewards_mint(amount)

        PubSub.register_to_new_transaction_by_address(tx.address)

        Archethic.send_new_transaction(tx)

        Logger.info("New mint rewards transaction sent with #{amount} token",
          transaction_address: Base.encode16(tx.address)
        )
    end
  end

  defp send_node_rewards do
    node_reward_tx = Reward.new_node_rewards()

    PubSub.register_to_new_transaction_by_address(node_reward_tx.address)

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
