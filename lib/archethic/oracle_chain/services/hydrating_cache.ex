defmodule Archethic.OracleChain.Services.HydratingCache do
  @moduledoc """
  This module is responsible for :
  - Run the hydrating function associated with this key at a given interval
  - Discard the value after some time
  - Return the value when requested
  """
  use GenServer
  @vsn Mix.Project.config()[:version]

  alias Archethic.TaskSupervisor
  alias Archethic.Utils

  require Logger

  defmodule State do
    @moduledoc false
    defstruct([
      :mfa,
      :ttl,
      :ttl_timer,
      # refresh_interval :: Int | CronInterval
      :refresh_interval,
      :value,
      :hydrating_task,
      :hydrating_timer,
      :hydrating_function_timeout
    ])
  end

  @spec start_link(keyword()) ::
          {:ok, GenServer.on_start()} | {:error, term()}
  def start_link(arg \\ []) do
    GenServer.start_link(__MODULE__, arg, Keyword.take(arg, [:name]))
  end

  @spec get(GenServer.server(), integer()) :: {:ok, any()} | :error
  def get(server, timeout \\ 5000) do
    try do
      GenServer.call(server, :get, timeout)
    catch
      :exit, {:timeout, _} ->
        :error
    end
  end

  def init(options) do
    refresh_interval = Keyword.fetch!(options, :refresh_interval)
    mfa = Keyword.fetch!(options, :mfa)
    ttl = Keyword.get(options, :ttl, :infinity)
    hydrating_function_timeout = Keyword.get(options, :hydrating_function_timeout, 5000)

    # start hydrating as soon as init is done
    hydrating_timer = Process.send_after(self(), :hydrate, 0)

    ## Hydrate the value
    {:ok,
     %State{
       mfa: mfa,
       ttl: ttl,
       hydrating_function_timeout: hydrating_function_timeout,
       refresh_interval: refresh_interval,
       hydrating_timer: hydrating_timer
     }}
  end

  def handle_call(:get, _from, state = %State{value: nil}) do
    {:reply, :error, state}
  end

  def handle_call(:get, _from, state = %State{value: value}) when value != nil do
    {:reply, {:ok, value}, state}
  end

  def handle_info(
        :hydrate,
        state = %State{
          hydrating_function_timeout: hydrating_function_timeout,
          mfa: {m, f, a}
        }
      ) do
    hydrating_task =
      Task.Supervisor.async_nolink(TaskSupervisor, fn ->
        try do
          {:ok, apply(m, f, a)}
        rescue
          e ->
            {:error, e}
        end
      end)

    # we make sure that our hydrating function does not hang
    Process.send_after(self(), {:kill_hydrating_task, hydrating_task}, hydrating_function_timeout)

    {:noreply, %State{state | hydrating_task: hydrating_task}}
  end

  def handle_info({:kill_hydrating_task, %Task{pid: pid}}, state) do
    # Task.shutdown will not send DOWN msg
    Process.exit(pid, :kill)

    {:noreply, state}
  end

  def handle_info(
        {ref, result},
        state = %State{
          mfa: {m, f, a},
          ttl_timer: ttl_timer,
          ttl: ttl,
          hydrating_task: %Task{ref: ref_task}
        }
      )
      when ref == ref_task do
    # cancel current ttl if any
    if is_reference(ttl_timer) do
      Process.cancel_timer(ttl_timer)
    end

    # start new ttl timer
    ttl_timer =
      if is_integer(ttl) do
        Process.send_after(self(), :discard_value, ttl)
      else
        nil
      end

    new_state = %{state | ttl_timer: ttl_timer}

    case result do
      {:ok, value} ->
        {:noreply, %{new_state | value: value}}

      {:error, reason} ->
        Logger.error("#{m}.#{f}.#{inspect(a)} returns an error: #{inspect(reason)}")
        {:noreply, new_state}
    end
  end

  def handle_info(
        {:DOWN, _ref, :process, _, _},
        state = %State{refresh_interval: refresh_interval}
      ) do
    # we always receive a DOWN on success/error/timeout
    # so this is the best place to cleanup & start a new timer
    hydrating_timer = Process.send_after(self(), :hydrate, next_tick_in_seconds(refresh_interval))

    {:noreply, %{state | hydrating_task: nil, hydrating_timer: hydrating_timer}}
  end

  def handle_info(:discard_value, state) do
    {:noreply, %State{state | value: nil, ttl_timer: nil}}
  end

  defp next_tick_in_seconds(refresh_interval) do
    if is_binary(refresh_interval) do
      Utils.time_offset(refresh_interval)
    else
      refresh_interval
    end
  end
end
