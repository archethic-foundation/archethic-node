defmodule ArchethicWeb.TransactionCache do
  @table :transactions
  # 5 minutes
  @default_ttl 5 * 60 * 1000
  @moduledoc false
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_args) do
    :ets.new(@table, [:set, :public, :named_table])

    {:ok, []}
  end

  @doc """
  Retreive a value back from cache
  """
  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def handle_call({:get, key}, _, state) do
    result =
      case :ets.lookup(@table, key) do
        [{^key, value, ts}] ->
          Logger.info("Fetching from cache")
          d_ts = get_current_timestamp() - ts
          :ets.update_element(@table, key, {3, d_ts})
          value

        _ ->
          nil
      end

    {:reply, result, state}
  end

  @doc """
  Put a value into the cache
  """
  def put(key, value) do
    GenServer.cast(__MODULE__, {:put, key, value})
  end

  def handle_cast({:put, key, value}, state) do
    true = :ets.insert(@table, {key, value, get_current_timestamp()})
    schedule_key_delete(key)
    {:noreply, state}
  end

  def handle_info({:delete, key}, state) do
    case :ets.lookup(@table, key) do
      [{^key, _value, ts}] ->
        if get_current_timestamp() - ts >= @default_ttl do
          delete(key)
        else
          schedule_key_delete(key, get_current_timestamp() - ts)
        end

      _ ->
        :ok
    end

    {:noreply, state}
  end

  @doc """
  Delete an entry from the cache
  """
  def delete(key) do
    true = :ets.delete(@table, key)
    :ok
  end

  @doc """
  Runs a piece of code if not already cached
  """
  def resolve(key, resolver) when is_function(resolver, 0) do
    case get(key) do
      nil ->
        with result <- resolver.() do
          Logger.info("Caching results")
          put(key, result)
          {:ok, result}
        end

      term ->
        Logger.info("Found in cache")
        {:ok, term}
    end
  end

  # Return current get_current_timestamp
  defp get_current_timestamp, do: System.os_time(:millisecond)

  defp schedule_key_delete(key, ts \\ @default_ttl) do
    # We schedule the delete in every 5 minutes
    Process.send_after(self(), {:delete, key}, ts)
  end
end
