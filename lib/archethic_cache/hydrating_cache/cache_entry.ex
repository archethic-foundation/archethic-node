defmodule ArchethicCache.HydratingCache.CacheEntry do
  @moduledoc """
  This module is a finite state machine implementing a cache entry.
  There is one such Cache Entry FSM running per registered key.

  It is responsible for :
  - receiving request to get the value for the key it is associated with
  - Run the hydrating function associated with this key
  - Manage various timers
  """
  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]

  use Task
  require Logger

  defstruct([
    :running_func_task,
    :hydrating_func,
    :ttl,
    :refresh_interval,
    :key,
    :timer_func,
    :timer_discard,
    getters: [],
    value: :"$$undefined"
  ])

  @spec start_link([...]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link([fun, key, refresh_interval, ttl]) do
    GenStateMachine.start_link(__MODULE__, [fun, key, refresh_interval, ttl], [])
  end

  @impl GenStateMachine
  def init([fun, key, refresh_interval, ttl]) do
    # start hydrating at the needed refresh interval
    {:ok, timer} = :timer.send_after(refresh_interval, self(), :hydrate)

    ## Hydrate the value
    {:ok, :running,
     %__MODULE__{
       timer_func: timer,
       hydrating_func: fun,
       key: key,
       ttl: ttl,
       refresh_interval: refresh_interval
     }}
  end

  @impl GenStateMachine
  def handle_event(
        {:call, from},
        {:get, _requester},
        :idle,
        data = %__MODULE__{:value => :"$$undefined"}
      ) do
    ## Value is requested while fsm is iddle, return the value
    {:keep_state, data, [{:reply, from, {:error, :not_initialized}}]}
  end

  def handle_event({:call, from}, {:get, _requester}, :idle, data) do
    ## Value is requested while fsm is iddle, return the value
    {:next_state, :idle, data, [{:reply, from, data.value}]}
  end

  ## Call for value while hydrating function is running and we have no previous value
  ## We register the caller to send value later on, and we indicate caller to block
  def handle_event(
        {:call, from},
        {:get, requester},
        :running,
        data = %__MODULE__{value: :"$$undefined"}
      ) do
    previous_getters = data.getters
    Logger.warning("Get Value but undefined #{inspect(data)}")

    {:keep_state, %__MODULE__{data | getters: previous_getters ++ [requester]},
     [{:reply, from, {:ok, :answer_delayed}}]}
  end

  ## Call for value while hydrating function is running and we have a previous value
  ## We return the value to caller
  def handle_event({:call, from}, {:get, _requester}, :running, data) do
    {:next_state, :running, data, [{:reply, from, data.value}]}
  end

  def handle_event({:call, from}, {:register, fun, key, refresh_interval, ttl}, :running, data) do
    ## Registering a new hydrating function while previous one is running

    ## We stop the hydrating task if it is already running
    case data.running_func_task do
      pid when is_pid(pid) -> Process.exit(pid, :normal)
      _ -> :ok
    end

    ## And the timers triggering it and discarding value
    _ = maybe_stop_timer(data.timer_func)
    _ = maybe_stop_timer(data.timer_discard)

    ## Start new timer to hydrate at refresh interval
    {:ok, timer} = :timer.send_after(refresh_interval, self(), :hydrate)

    ## We trigger the update ( to trigger or not could be set at registering option )
    {:repeat_state,
     %__MODULE__{
       data
       | hydrating_func: fun,
         key: key,
         ttl: ttl,
         refresh_interval: refresh_interval,
         timer_func: timer
     }, [{:reply, from, :ok}]}
  end

  def handle_event({:call, from}, {:register, fun, key, refresh_interval, ttl}, _state, data) do
    Logger.info("Registering hydrating function for key :#{inspect(key)}")

    ## Setting hydrating function in other cases
    ## Hydrating function not running, we just stop the timers
    _ = maybe_stop_timer(data.timer_func)
    _ = maybe_stop_timer(data.timer_discard)

    ## Fill state with new hydrating function parameters
    data =
      Map.merge(data, %{
        :hydrating_func => fun,
        :ttl => ttl,
        :refresh_interval => refresh_interval
      })

    {:ok, timer} = :timer.send_after(refresh_interval, self(), :hydrate)

    ## We trigger the update ( to trigger or not could be set at registering option )
    {:next_state, :running,
     %__MODULE__{
       data
       | hydrating_func: fun,
         key: key,
         ttl: ttl,
         refresh_interval: refresh_interval,
         timer_func: timer
     }, [{:reply, from, :ok}]}
  end

  def handle_event(:info, :hydrate, :idle, data) do
    ## Time to rehydrate
    ## Hydrating the key, go to running state
    {:next_state, :running, data}
  end

  def handle_event(:enter, _event, :running, data) do
    Logger.info("Entering running state for key :#{inspect(data.key)}")
    ## At entering running state, we start the hydrating task
    me = self()

    hydrating_task =
      spawn(fn ->
        Logger.info("Running hydrating function for key :#{inspect(data.key)}")
        value = data.hydrating_func.()
        GenStateMachine.cast(me, {:new_value, data.key, value})
      end)

    ## we stay in running state
    {:next_state, :running, %__MODULE__{data | running_func_task: hydrating_task}}
  end

  def handle_event(:info, :discarded, state, data) do
    ## Value is discarded

    Logger.warning(
      "Key :#{inspect(data.key)}, Hydrating func #{inspect(data.hydrating_func)} discarded"
    )

    {:next_state, state, %__MODULE__{data | value: {:error, :discarded}, timer_discard: nil}}
  end

  def handle_event(:cast, {:new_value, _key, {:ok, value}}, :running, data) do
    ## We got result from hydrating function
    Logger.debug("Got new value for key :#{inspect(data.key)}  #{inspect(value)}")
    ## Stop timer on value ttl
    _ = maybe_stop_timer(data.timer_discard)

    ## Start hydrating timer
    {:ok, timer_hydrate} = :timer.send_after(data.refresh_interval, self(), :hydrate)

    ## notify waiting getters
    Enum.each(data.getters, fn {pid, _ref} ->
      send(pid, {:delayed_value, data.key, {:ok, value}})
    end)

    ## Start timer to discard new value if needed
    me = self()

    {:ok, timer_ttl} =
      case data.ttl do
        ttl when is_number(ttl) ->
          :timer.send_after(ttl, me, :discarded)

        _ ->
          {:ok, nil}
      end

    {:next_state, :idle,
     %__MODULE__{
       data
       | running_func_task: :undefined,
         value: {:ok, value},
         getters: [],
         timer_func: timer_hydrate,
         timer_discard: timer_ttl
     }}
  end

  def handle_event(:cast, {:new_value, key, {:error, reason}}, :running, data) do
    ## Got error new value for key
    Logger.warning(
      "Key :#{inspect(data.key)}, Hydrating func #{inspect(data.hydrating_func)} got error value #{inspect({key, {:error, reason}})}"
    )

    ## Error values can be discarded
    me = self()

    {:ok, timer_ttl} =
      case data.ttl do
        ttl when is_number(ttl) ->
          :timer.send_after(ttl, me, :discarded)

        _ ->
          {:ok, nil}
      end

    ## Start hydrating timer
    {:ok, timer_hydrate} = :timer.send_after(data.refresh_interval, self(), :hydrate)

    {:next_state, :idle,
     %__MODULE__{
       data
       | running_func_task: :undefined,
         getters: [],
         timer_func: timer_hydrate,
         timer_discard: timer_ttl
     }}
  end

  def handle_event(_type, _event, _state, data) do
    {:keep_state, data}
  end

  defp maybe_stop_timer(tref = {_, _}) do
    :timer.cancel(tref)
  end

  defp maybe_stop_timer(_else) do
    :ok
  end
end
