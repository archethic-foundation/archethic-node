defmodule UnirisNetwork.SharedSecretStore.ETSImpl do
  @moduledoc false

  @behaviour UnirisNetwork.SharedSecretStore.Impl

  @impl true
  @spec storage_nonce() :: binary()
  def storage_nonce() do
    [{_, nonce}] = :ets.lookup(:shared_secrets, :storage_nonce)
    nonce
  end

  @impl true
  @spec daily_nonce() :: binary()
  def daily_nonce() do
    [{_, nonce}] = :ets.lookup(:shared_secrets, :daily_nonce)
    nonce
  end

  @impl true
  @spec origin_public_keys() :: list(binary())
  def origin_public_keys() do
    [{_, keys}] = :ets.lookup(:shared_secrets, :origin_public_keys)
    keys
  end

  @impl true
  @spec set_daily_nonce(binary()) :: :ok
  def set_daily_nonce(nonce) when is_binary(nonce) do
    :ets.insert(:shared_secrets, {:daily_nonce, nonce})
  end

  @impl true
  @spec add_origin_public_key(<<_::264>>) :: :ok
  def add_origin_public_key(<<public_key::binary-33>>) do
    :ets.insert(:shared_secrets, {:origin_public_keys, origin_public_keys() ++ [public_key]})
  end
end
