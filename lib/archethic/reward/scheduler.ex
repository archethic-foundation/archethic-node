defmodule Archethic.Reward.Scheduler do
  @moduledoc false

  use GenServer

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  alias Archethic.Crypto

  alias Archethic.PubSub

  alias Archethic.DB

  alias Archethic.P2P.Node

  alias Archethic.Reward

  alias Archethic.Utils
  alias Archethic.Utils.DetectNodeResponsiveness

  require Logger

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc """
  Get the last node rewards scheduling date
  """
  @spec last_date() :: DateTime.t()
  def last_date do
    GenServer.call(__MODULE__, :last_date)
  end

  def init(args) do
    interval = Keyword.fetch!(args, :interval)
    PubSub.register_to_node_update()
    {:ok, %{interval: interval}, :hibernate}
  end

  def handle_info(
        {:node_update,
         %Node{authorized?: true, available?: true, first_public_key: first_public_key}},
        state = %{interval: interval}
      ) do
    if Crypto.first_node_public_key() == first_public_key do
      case Map.get(state, :timer) do
        nil ->
          timer = schedule(interval)
          Logger.info("Start the network pool reward scheduler")
          {:noreply, Map.put(state, :timer, timer), :hibernate}

        _ ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info(
        {:node_update, %Node{authorized?: false, first_public_key: first_public_key}},
        state = %{timer: timer}
      ) do
    if Crypto.first_node_public_key() == first_public_key do
      Process.cancel_timer(timer)
      {:noreply, Map.delete(state, :timer)}
    else
      {:noreply, state}
    end
  end

  def handle_info(
        {:node_update, %Node{available?: false, first_public_key: first_public_key}},
        state = %{timer: timer}
      ) do
    if Crypto.first_node_public_key() == first_public_key do
      Process.cancel_timer(timer)
      {:noreply, Map.delete(state, :timer)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:node_update, _}, state), do: {:noreply, state}

  def handle_info(:mint_rewards, state = %{interval: interval}) do
    timer = schedule(interval)

    case DB.get_latest_burned_fees() do
      0 ->
        Logger.info("No mint rewards transaction needed")

      amount ->
        tx = Reward.new_rewards_mint(amount)

        if Reward.initiator?() do
          Archethic.send_new_transaction(tx)

          Logger.info("New mint rewards transaction sent with #{amount} token",
            transaction_address: Base.encode16(tx.address)
          )
        else
          DetectNodeResponsiveness.start_link(tx.address, fn count ->
            if Reward.initiator?(count) do
              Logger.debug("Mint secret creation...attempt #{count}",
                transaction_address: Base.encode16(tx.address)
              )

              Logger.info("New mint rewards transaction sent with #{amount} token",
                transaction_address: Base.encode16(tx.address)
              )

              Archethic.send_new_transaction(tx)
            end
          end)
        end
    end

    {:noreply, Map.put(state, :timer, timer), :hibernate}
  end

  def handle_call(:last_date, _, state = %{interval: interval}) do
    {:reply, get_last_date(interval), state}
  end

  def handle_cast({:new_conf, conf}, state) do
    case Keyword.get(conf, :interval) do
      nil ->
        {:noreply, state}

      new_interval ->
        {:noreply, Map.put(state, :interval, new_interval)}
    end
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
    GenServer.cast(__MODULE__, {:new_conf, conf})
  end
end
