defmodule ArchethicWeb.DashboardAggregatorAggregator do
  @moduledoc """
  This module regularly ask all the other nodes for their DashboardAggregator data

  The state is similar to DashboardAggregator but the bucket key
  is `{node_first_public_key, datetime}` instead of `datetime`
  """

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetDashboardData
  alias Archethic.P2P.Message.DashboardData
  alias Archethic.TaskSupervisor

  use GenServer
  @vsn Mix.Project.config()[:version]
  @timeout_seconds 2
  @request_interval_seconds 60
  @clean_interval_seconds 60
  @history_seconds 3600

  # The keys are a pair: {node_first_public_key, datetime}
  defstruct buckets: %{}

  # ----------------------------
  # API
  # ----------------------------

  @spec start_link(args :: list()) :: GenServer.on_start()
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @spec get_all() :: %{DateTime.t() => list(pos_integer())}
  def get_all() do
    GenServer.call(__MODULE__, :get_all)
  end

  @spec get_since(DateTime.t()) :: %{DateTime.t() => list(pos_integer())}
  def get_since(since) do
    GenServer.call(__MODULE__, {:get_since, since})
  end

  # ----------------------------
  # CALLBACKS
  # ----------------------------

  def init(_args) do
    # Start the clean_state loop
    Process.send_after(self(), :clean_state, @clean_interval_seconds * 1_000)

    # Immediately start to request other nodes data
    Process.send_after(self(), :request_other_nodes, 0)

    {:ok, %__MODULE__{}}
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

  # ----------------------------
  # INTERNAL FUNCTIONS
  # ----------------------------

  # start a (unlinked) task for every node (included current node)
  defp async_request_other_nodes(pid, buckets) do
    P2P.authorized_and_available_nodes()
    |> zip_nodes_with_latest_request(buckets)
    |> Enum.each(fn {node, since} ->
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
    end)
  end

  defp prefix_buckets(first_public_key, buckets) do
    buckets
    |> Enum.map(fn {datetime, durations} ->
      {{first_public_key, datetime}, durations}
    end)
    |> Enum.into(%{})
  end

  # TODO: can be optimized by looping only once
  defp zip_nodes_with_latest_request(nodes, buckets) do
    Enum.map(nodes, fn node ->
      %Node{first_public_key: first_public_key} = node
      {node, node_latest_request(buckets, first_public_key)}
    end)
  end

  defp node_latest_request(buckets, first_public_key) do
    buckets
    |> Map.keys()
    |> Enum.filter(fn
      {^first_public_key, _datetime} -> true
      _ -> false
    end)
    |> Enum.max_by(&elem(&1, 1), DateTime, fn -> {first_public_key, nil} end)
    |> elem(1)
  end

  defp drop_old_buckets(buckets) do
    now = DateTime.utc_now()

    Enum.reject(buckets, fn {{_first_public_key, datetime}, _value} ->
      DateTime.diff(now, datetime, :second) > @history_seconds
    end)
    |> Enum.into(%{})
  end
end
