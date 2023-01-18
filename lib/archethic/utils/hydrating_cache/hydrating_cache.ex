defmodule Archethic.Utils.HydratingCache do
  @moduledoc """
  GenServer implementing the hydrating cache itself.
  It receives queries from clients requesting the cache, and manage the cache entries FSMs
  """
  alias Archethic.Utils.HydratingCache.CacheEntry

  use GenServer

  require Logger

  @type result ::
          {:ok, any()}
          | {:error, :timeout}
          | {:error, :not_registered}

  def start_link({name, initial_keys}) do
    GenServer.start_link(__MODULE__, [name, initial_keys], name: :"#{__MODULE__}.#{name}")
  end

  @doc ~s"""
  Registers a function that will be computed periodically to update the cache.

  Arguments:
    - `fun`: a 0-arity function that computes the value and returns either
      `{:ok, value}` or `{:error, reason}`.
    - `key`: associated with the function and is used to retrieve the stored
    value.
    - `ttl` ("time to live"): how long (in milliseconds) the value is stored
      before it is discarded if the value is not refreshed.
    - `refresh_interval`: how often (in milliseconds) the function is
      recomputed and the new value stored. `refresh_interval` must be strictly
      smaller than `ttl`. After the value is refreshed, the `ttl` counter is
      restarted.

  The value is stored only if `{:ok, value}` is returned by `fun`. If `{:error,
  reason}` is returned, the value is not stored and `fun` must be retried on
  the next run.
  """
  @spec register_function(
          hydrating_cache :: pid(),
          fun :: (() -> {:ok, any()} | {:error, any()}),
          key :: any,
          ttl :: non_neg_integer(),
          refresh_interval :: non_neg_integer()
        ) :: :ok
  def register_function(hydrating_cache, fun, key, ttl, refresh_interval)
      when is_function(fun, 0) and is_integer(ttl) and ttl > 0 and
             is_integer(refresh_interval) and
             refresh_interval < ttl do
    GenServer.call(hydrating_cache, {:register, fun, key, ttl, refresh_interval})
  end

  @doc ~s"""
  Get the value associated with `key`.

  Details:
    - If the value for `key` is stored in the cache, the value is returned
      immediately.
    - If a recomputation of the function is in progress, the last stored value
      is returned.
    - If the value for `key` is not stored in the cache but a computation of
      the function associated with this `key` is in progress, wait up to
      `timeout` milliseconds. If the value is computed within this interval,
      the value is returned. If the computation does not finish in this
      interval, `{:error, :timeout}` is returned.
    - If `key` is not associated with any function, return `{:error,
      :not_registered}`
  """
  @spec get(pid(), any(), non_neg_integer(), Keyword.t()) :: result
  def get(cache, key, timeout \\ 30_000, _opts \\ [])
      when is_integer(timeout) and timeout > 0 do
    Logger.debug("Getting key #{inspect(key)} from hydrating cache #{inspect(cache)}")

    GenServer.call(cache, {:get, key}, timeout)
  end

  @impl GenServer
  def init([name, keys]) do
    Logger.info("Starting Hydrating cache for service #{inspect(name)}")

    ## start a dynamic supervisor for the cache entries/keys
    {:ok, keys_sup} =
      DynamicSupervisor.start_link(
        name: :"Archethic.Utils.HydratingCache.CacheEntry.KeysSupervisor.#{name}",
        strategy: :one_for_one
      )

    me = self()

    ## start a supervisor to manage the initial keys insertion workers
    {:ok, initial_keys_worker_sup} = Task.Supervisor.start_link()

    ## Registering initial keys
    _ =
      Task.Supervisor.async_stream_nolink(
        initial_keys_worker_sup,
        keys,
        fn
          {provider, mod, func, params, refresh_rate} ->
            Logger.debug(
              "Registering hydrating function. Provider: #{inspect(provider)} Hydrating function:
              #{inspect(mod)}.#{inspect(func)}(#{inspect(params)}) Refresh rate: #{inspect(refresh_rate)}"
            )

            GenServer.call(
              me,
              {:register, fn -> apply(mod, func, params) end, provider, 75_000, refresh_rate}
            )

          other ->
            Logger.error("Hydrating cache: Invalid configuration entry: #{inspect(other)}")
        end,
        on_timeout: :kill_task
      )
      |> Stream.filter(&match?({:ok, {:ok, _}}, &1))
      |> Enum.to_list()

    ## stop the initial keys worker supervisor
    Supervisor.stop(initial_keys_worker_sup)
    {:ok, %{:keys => keys, keys_sup: keys_sup}}
  end

  @impl true

  def handle_call({:get, key}, _from, state) do
    case Map.get(state, key, :undefined) do
      :undefined ->
        {:reply, {:error, :not_registered}, state}

      pid ->
        value = :gen_statem.call(pid, :get)
        IO.puts("value #{inspect(value)}")

        {:reply, value, state}
    end
  end

  def handle_call({:register, fun, key, ttl, refresh_interval}, _from, state) do
    ## Called when asked to register a function
    case Map.get(state, key) do
      nil ->
        ## New key, we start a cache entry fsm
        {:ok, pid} =
          DynamicSupervisor.start_child(
            state.keys_sup,
            {CacheEntry, [fun, key, ttl, refresh_interval]}
          )

        {:reply, :ok, Map.put(state, key, pid)}

      pid ->
        ## Key already exists, no need to start fsm
        case :gen_statem.call(pid, {:register, fun, key, ttl, refresh_interval}) do
          :ok ->
            {:reply, :ok, Map.put(state, key, pid)}

          error ->
            {:reply, {:error, error}, Map.put(state, key, pid)}
        end
    end
  end

  def handle_call(unmanaged, _from, state) do
    Logger.warning("Cache received unmanaged call: #{inspect(unmanaged)}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:get, from, key}, state) do
    case Map.get(state, key, :undefined) do
      :undefined ->
        send(from, {:error, :not_registered})
        {:noreply, state}

      pid ->
        :gen_statem.cast(pid, {:get, from})
        {:noreply, state}
    end
  end

  def handle_cast({:register, fun, key, ttl, refresh_interval}, state) do
    handle_call({:register, fun, key, ttl, refresh_interval}, nil, state)
    {:noreply, state}
  end

  def handle_cast(unmanaged, state) do
    Logger.warning("Cache received unmanaged cast: #{inspect(unmanaged)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(unmanaged, state) do
    Logger.warning("Cache received unmanaged info: #{inspect(unmanaged)}")
    {:noreply, state}
  end
end
