defmodule Archethic.Utils.HydratingCache do
  @moduledoc """
  GenServer implementing the hydrating cache itself.
  There should be one Hydrating per service ( ex : UCO price, meteo etc...)
  It receives queries from clients requesting the cache, and manage the cache entries FSMs
  """
  alias Archethic.Utils.HydratingCache.CacheEntry

  use GenServer
  @vsn Mix.Project.config()[:version]

  require Logger

  @type result ::
          {:ok, any()}
          | {:error, :timeout}
          | {:error, :not_registered}

  def start_link([name, initial_keys]) do
    GenServer.start_link(__MODULE__, [name, initial_keys], name: name)
  end

  def start_link(name, initial_keys \\ []) do
    start_link([name, initial_keys])
  end

  @doc ~s"""
  Registers a function that will be computed periodically to update the cache.

  Arguments:
    - `hydrating_cache`: the pid of the hydrating cache.
    - `fun`: a 0-arity function that computes the value and returns either
      `{:ok, value}` or `{:error, reason}`.
    - `key`: associated with the function and is used to retrieve the stored
    value.
    - `refresh_interval`: how often (in milliseconds) the function is
      recomputed and the new value stored. `refresh_interval` must be strictly
      smaller than `ttl`. After the value is refreshed, the `ttl` counter is
      restarted.
    - `ttl` ("time to live"): how long (in milliseconds) the value is stored
      before it is discarded if the value is not refreshed.


  The value is stored only if `{:ok, value}` is returned by `fun`. If `{:error,
  reason}` is returned, the value is not stored and `fun` must be retried on
  the next run.
  """
  @spec register_function(
          hydrating_cache :: pid(),
          fun :: (() -> {:ok, any()} | {:error, any()}),
          key :: any,
          refresh_interval :: non_neg_integer(),
          ttl :: non_neg_integer() | :infinity
        ) :: term()
  def register_function(hydrating_cache, fun, key, refresh_interval, ttl)
      when is_function(fun, 0) and
             is_integer(refresh_interval) and
             (refresh_interval < ttl or ttl == :infinity) do
    GenServer.call(hydrating_cache, {:register, fun, key, refresh_interval, ttl})
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
  @spec get(atom(), any(), non_neg_integer()) :: {:ok, term()} | {:error, atom()}
  def get(hydrating_cache, key, timeout \\ 1_000)
      when is_integer(timeout) and timeout > 0 do
    Logger.debug(
      "Getting key #{inspect(key)} from hydrating cache #{inspect(hydrating_cache)} for #{inspect(self())}"
    )

    case GenServer.call(hydrating_cache, {:get, key}, timeout) do
      {:ok, :answer_delayed} ->
        receive do
          {:delayed_value, _, value} ->
            value

          other ->
            Logger.warning("Unexpected return value #{inspect(other)}")
            {:error, :unexpected_value}
        after
          timeout ->
            Logger.warning(
              "Timeout waiting for delayed value for key #{inspect(key)} from hydrating cache #{inspect(hydrating_cache)}"
            )

            {:error, :timeout}
        end

      other_result ->
        other_result
    end
  end

  def get_all(hydrating_cache) do
    GenServer.call(hydrating_cache, :get_all)
  end

  @impl GenServer
  def init([name, initial_keys]) do
    Logger.info("Starting Hydrating cache for service #{inspect("#{__MODULE__}.#{name}")}")

    ## start a dynamic supervisor for the cache entries/keys
    {:ok, keys_sup} =
      DynamicSupervisor.start_link(
        name: :"Archethic.Utils.HydratingCache.CacheEntry.KeysSupervisor.#{name}",
        strategy: :one_for_one
      )

    ## Create child for each initial key
    child_specs =
      initial_keys
      |> Enum.map(fn {provider, mod, func, params, refresh_interval, ttl} ->
        {CacheEntry, [fn -> apply(mod, func, params) end, provider, refresh_interval, ttl]}
      end)

    ## Registering initial keys
    keys =
      Enum.reduce(child_specs, %{}, fn child = {_, [_, provider, _, _]}, acc ->
        {:ok, cache_entry} = DynamicSupervisor.start_child(keys_sup, child)
        Map.put(acc, provider, cache_entry)
      end)

    {:ok, %{keys: keys, keys_sup: keys_sup}}
  end

  @impl GenServer
  def handle_call({:get, key}, from, state = %{keys: keys}) do
    case Map.get(keys, key) do
      nil ->
        Logger.warning("HydratingCache no entry for #{inspect(key)}")
        {:reply, {:error, :not_registered}, state}

      pid ->
        value = GenStateMachine.call(pid, {:get, from})
        {:reply, value, state}
    end
  end

  def handle_call(:get_all, _from, state = %{keys: keys}) do
    Logger.debug(
      "Getting all keys from hydrating cache, current keys are #{inspect(keys)} sup: #{inspect(state.keys_sup)}"
    )

    {:ok, fetching_values_supervisor} = Task.Supervisor.start_link()

    result =
      Task.Supervisor.async_stream_nolink(
        fetching_values_supervisor,
        keys,
        fn {key, pid} ->
          case GenStateMachine.call(pid, {:get, {self(), nil}}) do
            {:ok, :answer_delayed} ->
              receive do
                {:delayed_value, _, {:ok, value}} ->
                  Logger.debug(
                    "Got delayed value for key #{inspect(value)} from hydrating cache #{inspect(self())}"
                  )

                  {:ok, value}

                other ->
                  Logger.warning("Unexpected return value #{inspect(other)}")
                  {:error, :unexpected_value}
              after
                3_000 ->
                  Logger.warning(
                    "Timeout waiting for delayed value for key #{inspect(key)} from hydrating cache #{inspect(self())}"
                  )

                  {:error, :timeout}
              end

            other ->
              other
          end
        end,
        on_timeout: :kill_task
      )
      |> Stream.filter(&match?({:ok, {:ok, _}}, &1))
      |> Stream.map(fn
        {_, {_, result}} ->
          result
      end)
      |> Enum.to_list()

    {:reply, result, state}
  end

  def handle_call({:register, fun, key, refresh_interval, ttl}, _from, state = %{keys: keys}) do
    Logger.debug("Registering hydrating function for #{inspect(key)}")
    ## Called when asked to register a function
    case Map.get(keys, key) do
      nil ->
        ## New key, we start a cache entry fsm
        {:ok, pid} =
          DynamicSupervisor.start_child(
            state.keys_sup,
            {CacheEntry, [fun, key, refresh_interval, ttl]}
          )

        {:reply, :ok, %{state | keys: Map.put(keys, key, pid)}}

      pid ->
        ## Key already exists, no need to start fsm
        case GenStateMachine.call(pid, {:register, fun, key, refresh_interval, ttl}) do
          :ok ->
            {:reply, :ok, %{state | keys: Map.put(keys, key, pid)}}

          error ->
            {:reply, {:error, error}, state}
        end
    end
  end

  def handle_call(unmanaged, _from, state) do
    Logger.warning("Cache received unmanaged call: #{inspect(unmanaged)}")
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast(unmanaged, state) do
    Logger.warning("Cache received unmanaged cast: #{inspect(unmanaged)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(unmanaged, state) do
    Logger.warning("Cache received unmanaged info: #{inspect(unmanaged)}")
    {:noreply, state}
  end
end
