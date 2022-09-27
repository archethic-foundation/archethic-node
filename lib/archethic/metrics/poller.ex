defmodule Archethic.Metrics.Poller do
  @moduledoc """
  Worker which poll network metrics periodically and notify registered clients (ie. LiveView)
  """

  require Logger

  use GenServer

  alias Archethic.Metrics.Collector

  alias Archethic.P2P
  alias Archethic.P2P.Node

  def start_link(opts \\ []) do
    options = Keyword.get(opts, :options, name: __MODULE__)
    interval = Keyword.get(opts, :interval, 5_000)

    GenServer.start_link(__MODULE__, [interval], options)
  end

  def init([interval]) do
    timer = schedule_polling(interval)

    state = %{
      pid_refs: %{},
      interval: interval,
      timer: timer
    }

    {:ok, state}
  end

  @doc """
  Register a process to monitor and get network metrics
  """
  @spec monitor() :: :ok
  def monitor(name \\ __MODULE__) do
    GenServer.call(name, :monitor)
  end

  def handle_call(:monitor, {pid, _tag}, state) do
    {:reply, :ok, register_process(pid, state)}
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
        {first_public_key, Collector.fetch_metrics(ip, port)}
      end,
      on_timeout: :kill_task
    )
  end

  defp schedule_polling(interval) do
    Process.send_after(self(), :poll_metrics, interval)
  end

  defp dispatch_metrics(metrics, node_public_key, pid_refs) do
    Enum.each(pid_refs, fn {pid_k, _pid_v} ->
      do_dispatch_update(pid_k, metrics, node_public_key)
    end)
  end

  defp do_dispatch_update(pid, data, node_key) do
    send(pid, {:update_data, data, node_key})
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
