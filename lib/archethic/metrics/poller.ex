defmodule Archethic.Metrics.Poller do
  @moduledoc """
  Worker which poll network metrics periodically and notify registered clients (ie. LiveView)
  """

  require Logger

  use GenServer
  @vsn Mix.Project.config()[:version]

  alias Archethic.Metrics.Collector

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.PubSub

  def start_link(opts \\ []) do
    options = Keyword.get(opts, :options, name: __MODULE__)
    interval = Keyword.get(opts, :interval, 5_000)

    GenServer.start_link(__MODULE__, [interval], options)
  end

  def init([interval]) do
    state = %{
      pid_refs: %{},
      interval: interval
    }

    if Archethic.up?() do
      Logger.info("Metric poller scheduler started")
      timer = schedule_polling(interval)
      {:ok, Map.put(state, :timer, timer)}
    else
      PubSub.register_to_node_status()
      {:ok, state}
    end
  end

  @doc """
  Register a process to monitor and get network metrics
  """
  @spec monitor() :: :ok
  def monitor(name \\ __MODULE__) do
    GenServer.call(name, :monitor)
  end

  def handle_call(:monitor, {pid, _tag}, state) do
    case Map.get(state, :timer) do
      nil ->
        {:reply, :ok, state}

      _ ->
        {:reply, :ok, register_process(pid, state)}
    end
  end

  def handle_info(:node_up, state = %{interval: interval}) do
    Logger.info("Metric poller scheduler started")
    timer = schedule_polling(interval)
    {:noreply, Map.put(state, :timer, timer)}
  end

  def handle_info(:node_down, state) do
    case Map.pop(state, :timer) do
      {nil, _} ->
        {:noreply, state}

      {timer, new_state} ->
        Process.cancel_timer(timer)
        {:noreply, new_state}
    end
  end

  def handle_info({:DOWN, _ref, :process, from_pid, _reason}, state) do
    {:noreply, deregister_process(from_pid, state)}
  end

  def handle_info(:poll_metrics, state = %{interval: interval, pid_refs: pid_refs}) do
    fetch_metrics()
    |> Stream.filter(&match?({:ok, {_, {:ok, _}}}, &1))
    |> Stream.map(fn {:ok, {node_key, {:ok, metrics}}} ->
      dispatch_metrics(metrics, node_key, pid_refs)
    end)
    |> Stream.run()

    dispatch_aggregate(pid_refs)

    timer = schedule_polling(interval)
    {:noreply, Map.put(state, :timer, timer)}
  end

  @spec fetch_metrics() :: Enumerable.t()
  def fetch_metrics do
    Task.async_stream(
      P2P.authorized_and_available_nodes(),
      fn %Node{
           ip: ip,
           http_port: port,
           first_public_key: first_public_key
         } ->
        if first_public_key == Archethic.Crypto.first_node_public_key(),
          do: {first_public_key, Collector.fetch_metrics({127, 0, 0, 1}, port)},
          else: {first_public_key, Collector.fetch_metrics(ip, port)}
      end,
      on_timeout: :kill_task
    )
  end

  defp schedule_polling(interval) do
    Process.send_after(self(), :poll_metrics, interval)
  end

  defp dispatch_metrics(metrics, node_public_key, pid_refs) do
    Enum.each(pid_refs, fn {pid, _} ->
      send(pid, {:update_data, metrics, node_public_key})
    end)
  end

  defp dispatch_aggregate(pid_refs) do
    Enum.each(pid_refs, fn {pid, _} ->
      send(pid, :aggregate)
    end)
  end

  defp register_process(pid, state) do
    mref = Process.monitor(pid)
    Map.update!(state, :pid_refs, &Map.put(&1, pid, %{monitor_ref: mref}))
  end

  defp deregister_process(from_pid, state = %{pid_refs: pid_refs}) do
    case Map.pop(pid_refs, from_pid) do
      {nil, _} ->
        state

      {%{monitor_ref: mref}, pid_refs} ->
        Process.demonitor(mref)
        Map.put(state, :pid_refs, pid_refs)
    end
  end
end
