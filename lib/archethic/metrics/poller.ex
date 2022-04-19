defmodule ArchEthic.Metrics.Poller do
  @moduledoc """
  Worker which poll network metrics periodically and notify registered clients (ie. LiveView)
  """

  require Logger

  use GenServer

  alias ArchEthic.Metrics.Collector

  def start_link(opts \\ []) do
    options = Keyword.get(opts, :options, name: __MODULE__)
    interval = Keyword.get(opts, :interval, 5_000)

    GenServer.start_link(__MODULE__, [interval], options)
  end

  defp default_state do
    default_metrics = %{
      "archethic_mining_full_transaction_validation_duration" => 0,
      "archethic_mining_proof_of_work_duration" => 0,
      "archethic_p2p_send_message_duration" => 0,
      "tps" => 0
    }

    %{pid_refs: %{}, data: default_metrics}
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

  defp dipatch_updates(%{data: data, pid_refs: pid_refs}) do
    pid_refs
    |> Task.async_stream(fn {pid_k, _pid_v} -> send(pid_k, {:update_data, data}) end)
    |> Stream.run()
  end

  defp register_process(pid, state) do
    mref = Process.monitor(pid)
    new_state = Map.update!(state, :pid_refs, &Map.put(&1, pid, %{monitor_ref: mref}))
    dipatch_updates(new_state)
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

  defp process_new_state(current_state = %{pid_refs: pid_refs}) do
    case Enum.empty?(pid_refs) do
      false ->
        Collector.get_node_endpoints()
        |> Collector.retrieve_network_metrics()
        |> then(&Map.put(current_state, :data, &1))
        |> tap(&dipatch_updates/1)

      true ->
        current_state
    end
  end
end
