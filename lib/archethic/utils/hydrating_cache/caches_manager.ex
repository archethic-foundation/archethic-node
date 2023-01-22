defmodule Archethic.Utils.HydratingCache.CachesManager do
  @moduledoc """
  This module is used to manage (create and delete) hydrating caches.
  At start it will read the configuration and start a cache per service.
  """
  use GenServer
  require Logger
  alias Archethic.Utils.HydratingCache

  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @doc """
  Start a new hydrating cache process to hold the values from a service.
  This is a synchronous call, it will block until the cache is started and
  hydrating process for initial keys is started.
  """
  @spec new_service_sync(
          name :: String.t(),
          initial_keys :: list()
        ) :: {:error, any} | {:ok, pid}
  def new_service_sync(name, initial_keys) do
    Logger.info("Starting new service sync #{name}")
    GenServer.call(__MODULE__, {:new_service_sync, name, initial_keys})
  end

  @doc """
    Start a new hydrating cache process to hold the values from a service.
    This is an asynchronous call, it will return immediately.
  """
  def new_service_async(name, keys) do
    Logger.info("Starting new service async #{name}")
    GenServer.cast(__MODULE__, {:new_service_async, name, keys, self()})
  end

  @doc """
    Sync call to end a service cache.
  """
  def end_service_sync(name) do
    GenServer.call(__MODULE__, {:end_service, name})
  end

  @impl true
  def init(_args) do
    manager_conf = Application.get_env(:archethic, __MODULE__, [])

    {:ok, caches_sup} =
      DynamicSupervisor.start_link(
        name: Archethic.Utils.HydratingCache.Manager.CachesSupervisor,
        strategy: :one_for_one
      )

    Logger.info(
      "Starting hydrating cache manager #{inspect(__MODULE__)} with conf #{inspect(manager_conf)}"
    )

    Enum.each(manager_conf, fn {service, keys} ->
      Logger.info("Starting new service #{service}")
      new_service_async(service, keys)
    end)

    {:ok, %{:caches_sup => caches_sup}}
  end

  @impl true
  def handle_call({:new_service_sync, name, initial_keys}, _from, state) do
    Logger.info("Starting new service sync : #{name}")

    {:ok, pid} =
      DynamicSupervisor.start_child(
        state.caches_sup,
        HydratingCache.child_spec([name, initial_keys, []])
      )

    {:reply, {:ok, pid}, state}
  end

  @impl true
  def handle_cast({:new_service_async, name, keys, _requester}, state) do
    Logger.info("Starting new service async : #{name}")

    DynamicSupervisor.start_child(state.caches_sup, %{
      id: name,
      start: {HydratingCache, :start_link, [name, keys]}
    })

    Logger.info("Started new service #{name}")

    {:noreply, state}
  end

  def handle_cast(_, state) do
    {:noreply, state}
  end
end
