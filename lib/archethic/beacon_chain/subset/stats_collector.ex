defmodule Archethic.BeaconChain.Subset.StatsCollector do
  @moduledoc """
  Get the networks stats locally and remotely

  Uses 2 job caches:
  - cache_get: cache the aggregation of local stats
  - cache_fetch: cache the I/O to fetch remote stats

  It subscribes to 2 events to start and stop both jobs ASAP
  Jobs are also started by the get/fetch function if needed
  """

  @vsn 1
  @timeout :archethic
           |> Application.compile_env(__MODULE__, [])
           |> Keyword.get(:timeout, :timer.minutes(1))

  use GenServer

  alias Archethic.P2P
  alias Archethic.Election
  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.NetworkCoordinates
  alias Archethic.Utils.JobCache
  alias Archethic.PubSub

  require Logger

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
  Get the local stats if current node is beacon storage node
  """
  @spec get(DateTime.t(), pos_integer()) :: %{binary() => Nx.Tensor.t()}
  def get(summary_time, timeout \\ @timeout) do
    JobCache.get!(
      {:get, summary_time},
      function: fn ->
        get_current_node_subsets(summary_time)
        |> do_get_stats()
      end,
      timeout: timeout
    )
  catch
    :exit, _ -> %{}
  end

  @doc """
  Fetch the stats of given summary from beacon_nodes
  """
  @spec fetch(DateTime.t(), pos_integer()) :: Nx.Tensor.t()
  def fetch(summary_time, timeout \\ @timeout) do
    JobCache.get!(
      {:fetch, summary_time},
      function: fn -> do_fetch_stats(summary_time) end,
      timeout: timeout
    )
  catch
    :exit, _ -> Nx.tensor(0)
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
    {:ok, :no_state}
  end

  def handle_info({:next_summary_time, next_summary_time}, state) do
    summary_time = BeaconChain.previous_summary_time(next_summary_time)

    maybe_start_job({:get, summary_time})
    maybe_start_job({:fetch, summary_time})

    {:noreply, state}
  end

  def handle_info(:self_repair_sync, state) do
    summary_time = BeaconChain.previous_summary_time(DateTime.utc_now())

    maybe_stop_job({:get, summary_time})
    maybe_stop_job({:fetch, summary_time})

    {:noreply, state}
  end

  # ------------------------------------------------------------
  #              _            _
  #   _ __  _ __(___   ____ _| |_ ___
  #  | '_ \| '__| \ \ / / _` | __/ _ \
  #  | |_) | |  | |\ V | (_| | ||  __/
  #  | .__/|_|  |_| \_/ \__,_|\__\___|
  #  |_|
  # ------------------------------------------------------------

  defp maybe_start_job({action, summary_time}) do
    case get_current_node_subsets(summary_time) do
      [] ->
        nil

      subsets ->
        JobCache.start(
          immediate: true,
          name_key: {action, summary_time},
          function: fn ->
            case action do
              :get ->
                do_get_stats(subsets)

              :fetch ->
                do_fetch_stats(summary_time)
            end
          end
        )
    end
  end

  defp maybe_stop_job(key) do
    JobCache.stop(key)
  end

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
