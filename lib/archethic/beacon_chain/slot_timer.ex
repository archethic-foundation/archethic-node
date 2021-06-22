defmodule ArchEthic.BeaconChain.SlotTimer do
  @moduledoc """
  Handle the scheduling of the beacon slots creation
  """

  use GenServer

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.SubsetRegistry

  alias ArchEthic.Crypto

  alias ArchEthic.P2P.Node

  alias ArchEthic.PubSub

  alias ArchEthic.Utils

  require Logger

  @doc """
  Create a new slot timer
  """
  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @doc """
  Give the next beacon chain slot using the `SlotTimer` interval
  """
  @spec next_slot(DateTime.t()) :: DateTime.t()
  def next_slot(date_from = %DateTime{microsecond: {0, 0}}) do
    get_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_next_run_dates(DateTime.to_naive(date_from))
    |> Enum.at(1)
    |> DateTime.from_naive!("Etc/UTC")
  end

  def next_slot(date_from = %DateTime{}) do
    get_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_next_run_date!(DateTime.to_naive(date_from))
    |> DateTime.from_naive!("Etc/UTC")
  end

  @doc """
  Returns the previous slot from the given date
  """
  @spec previous_slot(DateTime.t()) :: DateTime.t()
  def previous_slot(date_from = %DateTime{microsecond: {0, 0}}) do
    get_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_previous_run_dates(DateTime.to_naive(date_from))
    |> Enum.at(1)
    |> DateTime.from_naive!("Etc/UTC")
  end

  def previous_slot(date_from = %DateTime{}) do
    get_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_previous_run_date!(DateTime.to_naive(date_from))
    |> DateTime.from_naive!("Etc/UTC")
  end

  @doc """
  Return the previous slot times
  """
  @spec previous_slots(DateTime.t()) :: list(DateTime.t())
  def previous_slots(date_from) do
    get_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_previous_run_dates(DateTime.utc_now() |> DateTime.to_naive())
    |> Stream.take_while(fn datetime ->
      datetime
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.compare(date_from) == :gt
    end)
    |> Stream.map(&DateTime.from_naive!(&1, "Etc/UTC"))
    |> Enum.to_list()
  end

  defp get_interval do
    [{_, interval}] = :ets.lookup(:archethic_slot_timer, :interval)
    interval
  end

  @doc false
  def init(opts) do
    interval = Keyword.get(opts, :interval)
    :ets.new(:archethic_slot_timer, [:named_table, :public, read_concurrency: true])
    :ets.insert(:archethic_slot_timer, {:interval, interval})

    PubSub.register_to_node_update()

    {:ok, %{interval: interval}}
  end

  @doc false
  def handle_info(
        {:node_update, %Node{authorized?: true, first_public_key: key}},
        state = %{interval: interval}
      ) do
    if key == Crypto.first_node_public_key() do
      state
      |> Map.get(:timer)
      |> cancel_timer()

      timer = schedule_new_slot(interval)
      {:noreply, Map.put(state, :timer, timer), :hibernate}
    else
      {:noreply, state}
    end
  end

  def handle_info({:node_update, %Node{authorized?: false, first_public_key: key}}, state) do
    if key == Crypto.first_node_public_key() do
      state
      |> Map.get(:timer)
      |> cancel_timer()

      {:noreply, Map.delete(state, :timer), :hibernate}
    else
      {:noreply, state}
    end
  end

  def handle_info(
        :new_slot,
        state = %{
          interval: interval
        }
      ) do
    timer = schedule_new_slot(interval)

    slot_time = DateTime.utc_now() |> Utils.truncate_datetime()

    Logger.debug("Trigger beacon slots creation at #{Utils.time_to_string(slot_time)}")

    Enum.each(BeaconChain.list_subsets(), fn subset ->
      [{pid, _}] = Registry.lookup(SubsetRegistry, subset)
      send(pid, {:create_slot, slot_time})
    end)

    {:noreply, Map.put(state, :timer, timer), :hibernate}
  end

  def handle_cast({:new_conf, conf}, state) do
    case Keyword.get(conf, :interval) do
      nil ->
        {:noreply, state}

      new_interval ->
        :ets.insert(:archethic_slot_timer, {:interval, new_interval})
        {:noreply, Map.put(state, :interval, new_interval)}
    end
  end

  defp schedule_new_slot(interval) do
    Process.send_after(self(), :new_slot, Utils.time_offset(interval) * 1000)
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  def config_change(nil), do: :ok

  def config_change(conf) do
    GenServer.cast(__MODULE__, {:new_conf, conf})
  end
end
