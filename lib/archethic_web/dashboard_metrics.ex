defmodule ArchethicWeb.DashboardMetrics do
  @moduledoc """
  This module listens to a :mining_completed event.

  Every event received is placed in a bucket. There is 1 bucket per minute.
  We keep track of the latest 60 buckets to have a 1 hour history for the dashboard.

  CAUTION:  if it's called very often, it will become a bottleneck
            if that happens, consider using an ETS table
  """

  alias Archethic.Crypto
  alias Archethic.PubSub
  alias Archethic.Utils

  use GenServer
  @vsn Mix.Project.config()[:version]
  @clean_interval_seconds 60
  @history_seconds 3600

  defstruct buckets: %{}

  # ----------------------------
  # API
  # ----------------------------
  @spec start_link(args :: list()) :: GenServer.on_start()
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc """
  Return the current node dashboard metrics
  """
  @spec get_all() :: %{
          DateTime.t() => list({Crypto.prepended_hash(), pos_integer()})
        }
  def get_all() do
    GenServer.call(__MODULE__, :get_all)
  end

  @doc """
  Return the current node dashboard metrics (since a given time)
  """
  @spec get_since(DateTime.t()) :: %{
          DateTime.t() => list({Crypto.prepended_hash(), pos_integer()})
        }
  def get_since(since) do
    GenServer.call(__MODULE__, {:get_since, since})
  end

  # ----------------------------
  # CALLBACKS
  # ----------------------------
  def init(_args) do
    # We subscribe to mining event
    PubSub.register_to_topic(:mining)

    # Start the clean_state loop
    Process.send_after(self(), :clean_state, @clean_interval_seconds * 1_000)

    {:ok, %__MODULE__{}}
  end

  def handle_call(:get_all, _from, state = %__MODULE__{buckets: buckets}) do
    {:reply, buckets, state}
  end

  def handle_call({:get_since, since}, _from, state = %__MODULE__{buckets: buckets}) do
    filtered_buckets =
      Enum.filter(buckets, fn {datetime, _} ->
        DateTime.compare(datetime, since) != :lt
      end)
      |> Enum.into(%{})

    {:reply, filtered_buckets, state}
  end

  def handle_info(
        {:mining_completed,
         [
           address: address,
           validation_time: validation_time,
           duration: duration,
           success?: _success?
         ]},
        state = %__MODULE__{buckets: buckets}
      ) do
    # TODO: use success? to provide different aggregations?

    bucket_key = bucket_key(validation_time)

    new_buckets =
      Map.update(buckets, bucket_key, [{address, duration}], &[{address, duration} | &1])

    {:noreply, %__MODULE__{state | buckets: new_buckets}}
  end

  def handle_info(:clean_state, state = %__MODULE__{buckets: buckets}) do
    now = DateTime.utc_now()
    current_bucket_key = bucket_key(now)

    new_buckets = drop_old_buckets(buckets)

    # if there is no bucket for the current time
    # we create it
    # it's useful so we can have zero-value data instead of null-value data
    new_buckets =
      if Map.has_key?(new_buckets, current_bucket_key) do
        new_buckets
      else
        Map.put(new_buckets, current_bucket_key, [])
      end

    # Continue the clean_state loop
    Process.send_after(self(), :clean_state, @clean_interval_seconds * 1_000)

    {:noreply, %__MODULE__{state | buckets: new_buckets}}
  end

  # ----------------------------
  # INTERNAL FUNCTIONS
  # ----------------------------
  defp bucket_key(datetime) do
    Utils.truncate_datetime(datetime, second?: true, microsecond?: true)
  end

  defp drop_old_buckets(buckets) do
    now = DateTime.utc_now()

    Enum.reject(buckets, fn {datetime, _value} ->
      DateTime.diff(now, datetime, :second) > @history_seconds
    end)
    |> Enum.into(%{})
  end
end
