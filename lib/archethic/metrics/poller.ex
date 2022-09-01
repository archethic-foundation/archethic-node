defmodule Archethic.Metrics.Poller do
  @moduledoc """
  Worker which poll network metrics periodically and notify registered clients (ie. LiveView)
  """

  require Logger

  use GenServer

  alias Archethic.Metrics.Collector

  def start_link(opts \\ []) do
    options = Keyword.get(opts, :options, name: __MODULE__)
    interval = Keyword.get(opts, :interval, 5_000)

    GenServer.start_link(__MODULE__, [interval], options)
  end

  defp default_state do
    %{pid_refs: %{}, data: default_metrics(), previous_data: default_metrics()}
  end

  defp default_metrics do
    %{
      "archethic_mining_full_transaction_validation_duration" => 0,
      "archethic_mining_proof_of_work_duration" => 0,
      "archethic_p2p_send_message_duration" => 0,
      "tps" => 0
    }
  end

  def init([interval]) do
    timer = schedule_polling(interval)

    state =
      default_state()
      |> Map.put(:interval, interval)
      |> Map.put(:timer, timer)

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

  def handle_info(:poll_metrics, current_state = %{interval: interval}) do
    new_state = process_new_state(current_state)
    timer = schedule_polling(interval)
    {:noreply, Map.put(new_state, :timer, timer)}
  end

  defp schedule_polling(interval) do
    Process.send_after(self(), :poll_metrics, interval)
  end

  defp dispatch_updates(%{data: data, pid_refs: pid_refs}) do
    pid_refs
    |> Task.async_stream(fn {pid_k, _pid_v} -> do_dispatch_update(pid_k, data) end)
    |> Stream.run()
  end

  defp do_dispatch_update(pid, data) do
    send(pid, {:update_data, data})
  end

  defp register_process(pid, state = %{data: data}) do
    mref = Process.monitor(pid)
    new_state = Map.update!(state, :pid_refs, &Map.put(&1, pid, %{monitor_ref: mref}))
    do_dispatch_update(pid, data)
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

  defp process_new_state(current_state = %{pid_refs: pid_refs}) when map_size(pid_refs) == 0,
    do: current_state

  defp process_new_state(current_state = %{previous_data: previous_data}) do
    fetched_data =
      Collector.get_node_endpoints()
      |> Collector.retrieve_network_metrics()

    new_data =
      Enum.reduce(previous_data, default_metrics(), fn {key, previous_value}, acc ->
        case Map.get(fetched_data, key) do
          nil ->
            Map.put(acc, key, 0)

          # If the fetched value is the same as the previous fetched data
          # We reset the counter to 0, as no more events have been accumulated
          ^previous_value ->
            Map.put(acc, key, 0)

          new_value when new_value != previous_value ->
            Map.put(acc, key, abs(new_value - previous_value))
        end
      end)

    new_state =
      current_state
      |> Map.put(:previous_data, fetched_data)
      |> Map.put(:data, new_data)

    dispatch_updates(new_state)
    new_state
  end
end
