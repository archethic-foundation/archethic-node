defmodule ArchethicWeb.Cache do
  @table :transactions
  # 5 minutes
  @default_ttl 5 * 60
  @moduledoc false

  @doc """
  Create a new ETS Cache if it doesn't already exists
  """
  def start do
    :ets.new(@table, [:set, :public, :named_table])
    :ok
  rescue
    ArgumentError -> {:error, :already_started}
  end

  @doc """
  Retreive a value back from cache
  """
  def get(key, ttl \\ @default_ttl) do
    case :ets.lookup(@table, key) do
      [{^key, value, ts}] ->
        if timestamp() - ts <= ttl do
          value
        end

      _else ->
        nil
    end
  end

  @doc """
  Put a value into the cache
  """
  def put(key, value) do
    true = :ets.insert(@table, {key, value, timestamp()})
    :ok
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
  def resolve(key, ttl \\ @default_ttl, resolver) when is_function(resolver, 0) do
    case get(key, ttl) do
      nil ->
        with {:ok, result} <- resolver.() do
          put(key, result)
          {:ok, result}
        end

      term ->
        {:ok, term}
    end
  end

  # Return current timestamp
  defp timestamp, do: DateTime.to_unix(DateTime.utc_now())
end
