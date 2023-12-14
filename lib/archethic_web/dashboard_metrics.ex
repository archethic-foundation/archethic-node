defmodule ArchethicWeb.DashboardMetrics do
  @moduledoc """
  This module listens to a :mining_completed event.

  Every event received is placed in a bucket. There is 1 bucket per minute.
  We keep track of the latest 60 buckets to have a 1 hour history for the dashboard.

  CAUTION:  if it's called very often, it will become a bottleneck
            if that happens, consider using an ETS table
  """

  alias Archethic.PubSub

  use GenServer
  @vsn Mix.Project.config()[:version]
  @clean_interval_seconds 60
  @history_seconds 3600

  defstruct buckets: %{}

  # API

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

  # CALLBACKS

  def init(_args) do
    # We subscribe to mining event
    PubSub.register_to_topic(:mining)

    # Start the clean_state loop
    Process.send_after(self(), :clean_state, @clean_interval_seconds * 1_000)

    {:ok, %__MODULE__{}}
  end

  def handle_call(:get_all, _from, state) do
    %__MODULE__{buckets: buckets} = state
    {:reply, buckets, state}
  end

  def handle_call({:get_since, since}, _from, state) do
    %__MODULE__{buckets: buckets} = state

    filtered_buckets =
      Enum.filter(buckets, fn {datetime, _} ->
        DateTime.compare(datetime, since) != :lt
      end)
      |> Enum.into(%{})

    {:reply, filtered_buckets, state}
  end

  def handle_info({:mining_completed, payload}, state) do
    %__MODULE__{buckets: buckets} = state
    [validation_time: validation_time, duration: duration, success?: _success?] = payload

    # TODO: use success? to provide different aggregations?

    bucket_key = bucket_key(validation_time)
    new_buckets = Map.update(buckets, bucket_key, [duration], &[duration | &1])

    {:noreply, %__MODULE__{state | buckets: new_buckets}}
  end

  def handle_info(:clean_state, state) do
    %__MODULE__{buckets: buckets} = state
    new_buckets = drop_old_buckets(buckets)

    # Continue the clean_state loop
    Process.send_after(self(), :clean_state, @clean_interval_seconds * 1_000)

    {:noreply, %__MODULE__{state | buckets: new_buckets}}
  end

  defp bucket_key(datetime) do
    timestamp = DateTime.to_unix(datetime)
    seconds = rem(timestamp, 60)
    DateTime.from_unix!(timestamp - seconds)
  end

  defp drop_old_buckets(buckets) do
    now = DateTime.utc_now()

    Enum.reject(buckets, fn {datetime, _value} ->
      DateTime.diff(now, datetime, :second) > @history_seconds
    end)
    |> Enum.into(%{})
  end
end
