defmodule ArchethicWeb.Explorer.TransactionCache do
  @table :transactions
  # 5 minutes
  @default_time 5 * 60 * 1000
  @moduledoc false
  use GenServer
  @vsn 1
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_args) do
    :ets.new(@table, [:set, :public, :named_table])

    {:ok, []}
  end

  @doc """
  Retrieve a value from cache
  """
  def get(date) do
    GenServer.call(__MODULE__, {:get, date})
  end

  def handle_call({:get, date}, _, state) do
    Logger.debug("Fetching from cache")

    result =
      case :ets.lookup(@table, date) do
        [{^date, value, deletion_timer}] ->
          Process.cancel_timer(deletion_timer)
          new_deletion_timer = schedule_delete(date)
          :ets.update_element(@table, date, {3, new_deletion_timer})
          value

        _ ->
          nil
      end

    {:reply, result, state}
  end

  @doc """
  Put a value into the cache
  """
  def put(date, value) do
    GenServer.cast(__MODULE__, {:put, date, value})
  end

  def handle_cast({:put, date, value}, state) do
    deletion_timer = schedule_delete(date)
    true = :ets.insert(@table, {date, value, deletion_timer})
    {:noreply, state}
  end

  def handle_info({:delete, date}, state) do
    true = :ets.delete(@table, date)
    {:noreply, state}
  end

  @doc """
  Runs a piece of code if not already cached
  """
  def resolve(date, resolver) when is_function(resolver, 0) do
    case get(date) do
      nil ->
        with result <- resolver.() do
          Logger.debug("Caching results")
          put(date, result)
          {:ok, result}
        end

      term ->
        Logger.debug("Found in cache")
        {:ok, term}
    end
  end

  defp schedule_delete(date, time \\ @default_time) do
    # We schedule the delete after 5 minutes
    Process.send_after(self(), {:delete, date}, time)
  end
end
