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
      P2P.list_nodes(),
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
    new_state = Map.update!(state, :pid_refs, &Map.put(&1, pid, %{monitor_ref: mref}))
    # do_dispatch_update(pid, data)
    new_state
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

  # defp process_new_state(current_state = %{pid_refs: pid_refs}) when map_size(pid_refs) == 0,
  #   do: current_state

  # defp process_new_state(current_state = %{previous_fetched_data: previous_fetched_data}) do
  #   fetched_data =
  #     Collector.get_node_endpoints()
  #     |> Collector.retrieve_network_metrics()

  #   new_data =
  #     Enum.reduce(fetched_data, default_metrics(), fn {key, fetched_value}, acc ->
  #       case Map.get(previous_fetched_data, key) do
  #         # If the fetched value is the same as the previous fetched data
  #         # We reset the counter to 0, as no more events have been accumulated
  #         ^fetched_value ->
  #           Map.put(acc, key, 0)

  #         previous_value ->
  #           Map.put(acc, key, fetched_value - previous_value)
  #       end
  #     end)

  #   new_state =
  #     current_state
  #     |> Map.update!(:previous_fetched_data, &Map.merge(&1, fetched_data))
  #     |> Map.put(:data, new_data)

  #   dispatch_updates(new_state)
  #   new_state
  # end
end
