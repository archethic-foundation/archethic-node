defmodule ArchethicWeb.DashboardMetricsAggregator do
  @moduledoc """
  This module regularly ask all the other nodes for their DashboardMetrics data

  The state is similar to DashboardMetrics but the bucket key
  is `{node_first_public_key, datetime}` instead of `datetime`
  """

  alias Archethic.Crypto
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetDashboardData
  alias Archethic.P2P.Message.DashboardData
  alias Archethic.PubSub
  alias Archethic.TaskSupervisor

  use GenServer
  @vsn Mix.Project.config()[:version]
  @timeout_seconds 2
  @request_interval_seconds 60
  @clean_interval_seconds 60
  @history_seconds 3600

  # The keys are a pair: {node_first_public_key, datetime}
  defstruct buckets: %{}, timer: nil

  # ----------------------------
  # API
  # ----------------------------

  @spec start_link(args :: list()) :: GenServer.on_start()
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @spec get_all() :: %{{Crypto.key(), DateTime.t()} => list(pos_integer())}
  def get_all() do
    GenServer.call(__MODULE__, :get_all)
  end

  @spec get_since(DateTime.t()) :: %{{Crypto.key(), DateTime.t()} => list(pos_integer())}
  def get_since(since) do
    GenServer.call(__MODULE__, {:get_since, since})
  end

  # ----------------------------
  # CALLBACKS
  # ----------------------------

  def init(_args) do
    # Start the clean_state loop
    Process.send_after(self(), :clean_state, @clean_interval_seconds * 1_000)

    # Start to request other nodes data only when bootstrap is done
    timer =
      if Archethic.up?() do
        Process.send_after(self(), :request_other_nodes, 1)
      else
        PubSub.register_to_node_status()
        nil
      end

    {:ok, %__MODULE__{timer: timer}}
  end

  def handle_call(:get_all, _from, state) do
    %__MODULE__{buckets: buckets} = state

    {:reply, buckets, state}
  end

  def handle_call({:get_since, since}, _from, state) do
    %__MODULE__{buckets: buckets} = state

    filtered_buckets =
      Enum.filter(buckets, fn {{_, datetime}, _} ->
        DateTime.compare(datetime, since) != :lt
      end)
      |> Enum.into(%{})

    {:reply, filtered_buckets, state}
  end

  def handle_info(:request_other_nodes, state) do
    %__MODULE__{buckets: buckets} = state
    async_request_other_nodes(self(), buckets)

    # Continue the request_other_nodes loop
    Process.send_after(self(), :request_other_nodes, @request_interval_seconds * 1_000)

    {:noreply, state}
  end

  def handle_info({:remote_buckets, remote_buckets}, state) do
    %__MODULE__{buckets: buckets} = state

    new_buckets = Map.merge(buckets, remote_buckets)
    {:noreply, %__MODULE__{state | buckets: new_buckets}}
  end

  def handle_info(:clean_state, state) do
    %__MODULE__{buckets: buckets} = state
    new_buckets = drop_old_buckets(buckets)

    # Continue the clean_state loop
    Process.send_after(self(), :clean_state, @clean_interval_seconds * 1_000)

    {:noreply, %__MODULE__{state | buckets: new_buckets}}
  end

  def handle_info(:node_up, state) do
    timer = Process.send_after(self(), :request_other_nodes, 1)
    {:noreply, %__MODULE__{state | timer: timer}}
  end

  def handle_info(:node_down, state) do
    %__MODULE__{timer: timer} = state
    Process.cancel_timer(timer)
    {:noreply, %__MODULE__{state | timer: nil}}
  end

  # ----------------------------
  # INTERNAL FUNCTIONS
  # ----------------------------

  # start a (unlinked) task for every node (included current node)
  defp async_request_other_nodes(pid, buckets) do
    P2P.authorized_and_available_nodes()
    |> zip_nodes_with_latest_request(buckets)
    |> Enum.each(fn {node, since} ->
      async_request_dashboard_data(pid, node, since)
    end)
  end

  defp async_request_dashboard_data(pid, node, since) do
    %Node{first_public_key: first_public_key} = node

    Task.Supervisor.start_child(
      TaskSupervisor,
      fn ->
        case P2P.send_message(
               node,
               %GetDashboardData{since: since},
               @timeout_seconds * 1000
             ) do
          {:ok, %DashboardData{buckets: buckets}} ->
            remote_buckets = prefix_buckets(first_public_key, buckets)
            send(pid, {:remote_buckets, remote_buckets})

          _ ->
            :ok
        end
      end
    )
  end

  defp prefix_buckets(first_public_key, buckets) do
    buckets
    |> Enum.map(fn {datetime, durations} ->
      {{first_public_key, datetime}, durations}
    end)
    |> Enum.into(%{})
  end

  defp zip_nodes_with_latest_request(nodes, buckets) do
    nodes_datetimes =
      Enum.group_by(
        buckets,
        fn {{first_public_key, _}, _} -> first_public_key end,
        fn {{_, datetime}, _} -> datetime end
      )

    Enum.map(nodes, fn node = %Node{first_public_key: first_public_key} ->
      last_datetime =
        nodes_datetimes
        |> Map.get(first_public_key, [])
        |> Enum.max(DateTime, fn -> nil end)

      {node, last_datetime}
    end)
  end

  defp drop_old_buckets(buckets) do
    now = DateTime.utc_now()

    Enum.reject(buckets, fn {{_first_public_key, datetime}, _value} ->
      DateTime.diff(now, datetime, :second) > @history_seconds
    end)
    |> Enum.into(%{})
  end
end
