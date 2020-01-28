defmodule UnirisNetwork.SharedSecretStore do
  @moduledoc false
  @behaviour UnirisNetwork.SharedSecretStore.Impl

  @impl true
  def storage_nonce do
    impl().storage_nonce()
  end

  @impl true
  def daily_nonce() do
    impl().daily_nonce()
  end

  @impl true
  def origin_public_keys() do
    impl().origin_public_keys()
  end

  @impl true
  def set_daily_nonce(daily_nonce) do
    impl().set_daily_nonce(daily_nonce)
  end

  @impl true
  def add_origin_public_key(public_key) do
    impl().add_origin_public_key(public_key)
  end

  defp impl(), do: Application.get_env(:uniris_network, :shared_secret_store, UnirisNetwork.SharedSecretStore.ETSImpl)
end
