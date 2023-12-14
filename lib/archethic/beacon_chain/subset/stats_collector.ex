defmodule Archethic.BeaconChain.Subset.StatsCollector do
  @moduledoc """
  Get the networks stats locally and remotely

  Uses 2 job caches:
  - cache_get: cache the aggregation of local stats
  - cache_fetch: cache the I/O
  """

  @vsn Mix.Project.config()[:version]
  @timeout :timer.minutes(1)
  use GenServer

  alias Archethic.P2P
  alias Archethic.Election
  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.NetworkCoordinates
  alias Archethic.Utils.JobCache
  alias Archethic.PubSub

  require Logger

  defstruct [:cache_fetch, :cache_get]

  # ------------------------------------------------------------
  #     _    ____ ___
  #    / \  |  _ |_ _|
  #   / _ \ | |_) | |
  #  / ___ \|  __/| |
  # /_/   \_|_|  |___|
  # ------------------------------------------------------------

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the local stats for the subsets this node is elected
  """
  @spec get(pos_integer()) :: %{binary() => Nx.Tensor.t()}
  def get(timeout \\ @timeout) do
    GenServer.call(__MODULE__, :get, timeout)
  end

  @doc """
  Fetch the stats from all subsets
  """
  @spec fetch(pos_integer()) :: Nx.Tensor.t()
  def fetch(timeout \\ @timeout) do
    GenServer.call(__MODULE__, :fetch, timeout)
  end

  # ------------------------------------------------------------
  #            _ _ _                _
  #   ___ __ _| | | |__   __ _  ___| | _____
  #  / __/ _` | | | '_ \ / _` |/ __| |/ / __|
  # | (_| (_| | | | |_) | (_| | (__|   <\__ \
  #  \___\__,_|_|_|_.__/ \__,_|\___|_|\_|___/
  # ------------------------------------------------------------
  def init(_) do
    PubSub.register_to_next_summary_time()
    PubSub.register_to_self_repair()
    {:ok, %__MODULE__{}}
  end

  def handle_call(:get, _from, state = %__MODULE__{cache_get: pid}) do
    stats =
      try do
        JobCache.get!(pid, @timeout)
      catch
        :exit, _ ->
          %{}
      end

    {:reply, stats, state}
  end

  def handle_call(:fetch, _from, state = %__MODULE__{cache_fetch: pid}) do
    stats =
      try do
        JobCache.get!(pid, @timeout)
      catch
        :exit, _ ->
          Nx.tensor(0)
      end

    {:reply, stats, state}
  end

  # When the summary happens, we fetch the stats
  # and keep the result in a cache
  def handle_info({:next_summary_time, next_summary_time}, state) do
    summary_time = BeaconChain.previous_summary_time(next_summary_time)

    # election of current node subsets
    new_state =
      case get_current_node_subsets(summary_time) do
        [] ->
          Logger.debug("Current node is elected to store 0 beacon subset")
          state

        subsets ->
          Logger.debug("Current node is elected to store #{length(subsets)} beacon subsets")

          {:ok, cache_fetch_pid} =
            JobCache.start_link(immediate: true, function: fn -> do_fetch_stats(summary_time) end)

          {:ok, cache_get_pid} =
            JobCache.start_link(immediate: true, function: fn -> do_get_stats(subsets) end)

          %__MODULE__{state | cache_fetch: cache_fetch_pid, cache_get: cache_get_pid}
      end

    {:noreply, new_state}
  end

  # When a self repair happens, nobody will ask us for the stats anymore
  # We can clear the caches
  def handle_info(
        :self_repair_sync,
        state = %__MODULE__{
          cache_fetch: cache_fetch_pid,
          cache_get: cache_get_pid
        }
      ) do
    if is_pid(cache_fetch_pid) do
      JobCache.stop(cache_fetch_pid)
    end

    if is_pid(cache_get_pid) do
      JobCache.stop(cache_get_pid)
    end

    {:noreply, %__MODULE__{state | cache_fetch: nil, cache_get: nil}}
  end

  # ------------------------------------------------------------
  #              _            _
  #   _ __  _ __(___   ____ _| |_ ___
  #  | '_ \| '__| \ \ / / _` | __/ _ \
  #  | |_) | |  | |\ V | (_| | ||  __/
  #  | .__/|_|  |_| \_/ \__,_|\__\___|
  #  |_|
  # ------------------------------------------------------------
  defp do_get_stats(subsets) do
    subsets
    |> Task.async_stream(
      fn subset ->
        stats = BeaconChain.get_network_stats(subset)

        {subset, stats}
      end,
      timeout: 10_000,
      on_timeout: :kill_task,
      ordered: false,
      max_concurrency: 256
    )
    |> Stream.filter(fn
      {:exit, :timeout} -> false
      _ -> true
    end)
    |> Stream.map(fn {:ok, res} -> res end)
    |> Enum.to_list()
    |> Enum.reduce(%{}, fn
      {subset, stats}, acc when map_size(stats) > 0 ->
        Map.put(acc, subset, stats)

      _, acc ->
        acc
    end)
  end

  defp do_fetch_stats(summary_time) do
    start_time = System.monotonic_time()
    stats = NetworkCoordinates.fetch_network_stats(summary_time)

    :telemetry.execute(
      [:archethic, :beacon_chain, :network_coordinates, :collect_stats],
      %{
        duration: System.monotonic_time() - start_time
      },
      %{matrix_size: Nx.size(stats)}
    )

    stats
  end

  defp get_current_node_subsets(summary_time) do
    authorized_nodes = P2P.authorized_and_available_nodes(summary_time, true)
    current_node = P2P.get_node_info()

    Enum.reduce(BeaconChain.list_subsets(), [], fn subset, acc ->
      beacon_nodes = Election.beacon_storage_nodes(subset, summary_time, authorized_nodes)

      if current_node in beacon_nodes do
        [subset | acc]
      else
        acc
      end
    end)
  end
end
