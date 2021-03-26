defmodule Uniris.SharedSecrets.MemTables.NetworkLookup do
  @moduledoc false

  alias Uniris.Crypto

  use GenServer

  @table_name :uniris_shared_secrets_network

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])
    {:ok, []}
  end

  @spec set_network_pool_address(binary()) :: :ok
  def set_network_pool_address(address) when is_binary(address) do
    true = :ets.insert(@table_name, {:network_pool_address, address})
    :ok
  end

  @spec get_network_pool_address :: binary()
  def get_network_pool_address do
    case :ets.lookup(@table_name, :network_pool_address) do
      [{_, key}] ->
        key

      _ ->
        ""
    end
  end

  @spec set_daily_nonce_public_key(Crypto.key()) :: :ok
  def set_daily_nonce_public_key(public_key) when is_binary(public_key) do
    true = :ets.insert(@table_name, {:daily_nonce, public_key})
    :ok
  end

  @spec get_daily_nonce_public_key :: Crypto.key()
  def get_daily_nonce_public_key do
    case :ets.lookup(@table_name, :daily_nonce) do
      [{_, key}] ->
        key

      _ ->
        ""
    end
  end
end
