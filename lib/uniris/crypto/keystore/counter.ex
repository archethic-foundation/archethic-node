defmodule Uniris.Crypto.KeystoreCounter do
  @moduledoc false

  use GenServer

  @table_name :uniris_keys_counters

  require Logger

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  def set_node_key_counter(nb) when is_integer(nb) and nb >= 0 do
    set_counter(:node, nb)
    Logger.info("Node key index incremented (#{nb})")
  end

  def set_node_shared_secrets_key_counter(nb) when is_integer(nb) and nb >= 0 do
    set_counter(:node_shared_secrets, nb)
    Logger.info("Node shared secrets key index incremented (#{nb})")
  end

  def set_network_pool_key_counter(nb) when is_integer(nb) and nb >= 0 do
    set_counter(:network_pool, nb)
    Logger.info("Network pool key index incremented (#{nb})")
  end

  defp set_counter(key, nb) do
    true = :ets.insert(@table_name, {key, nb})
    :ok
  end

  def get_node_key_counter, do: get_counter(:node)
  def get_node_shared_key_counter, do: get_counter(:node_shared_secrets)
  def get_network_pool_key_counter, do: get_counter(:network_pool)

  defp get_counter(key) do
    case :ets.lookup(@table_name, key) do
      [] ->
        0

      [{_, nb}] ->
        nb
    end
  end
end
