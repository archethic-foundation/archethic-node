defmodule Uniris.Crypto.SharedSecretsKeystore do
  @moduledoc false

  alias __MODULE__.SoftwareImpl
  alias Uniris.Crypto.SharedSecretsKeystoreImpl

  # TODO: detect the implementation to use (software, SGX)
  @default_impl SoftwareImpl

  @behaviour SharedSecretsKeystoreImpl

  def child_spec(opts), do: impl().child_spec(opts)

  @impl SharedSecretsKeystoreImpl
  def sign_with_node_shared_secrets_key(data), do: impl().sign_with_node_shared_secrets_key(data)

  @impl SharedSecretsKeystoreImpl
  def sign_with_node_shared_secrets_key(data, index),
    do: impl().sign_with_node_shared_secrets_key(data, index)

  @impl SharedSecretsKeystoreImpl
  def sign_with_network_pool_key(data), do: impl().sign_with_network_pool_key(data)

  @impl SharedSecretsKeystoreImpl
  def sign_with_network_pool_key(data, index), do: impl().sign_with_network_pool_key(data, index)

  @impl SharedSecretsKeystoreImpl
  def sign_with_daily_nonce_key(data, index), do: impl().sign_with_daily_nonce_key(data, index)

  @impl SharedSecretsKeystoreImpl
  def node_shared_secrets_public_key(index), do: impl().node_shared_secrets_public_key(index)

  @impl SharedSecretsKeystoreImpl
  def network_pool_public_key(index), do: impl().network_pool_public_key(index)

  @impl SharedSecretsKeystoreImpl
  def encrypt_node_shared_secrets_transaction_seed(key),
    do: impl().encrypt_node_shared_secrets_transaction_seed(key)

  @impl SharedSecretsKeystoreImpl
  def encrypt_network_pool_seed(key), do: impl().encrypt_network_pool_seed(key)

  @impl SharedSecretsKeystoreImpl
  def decrypt_and_set_node_shared_secrets_transaction_seed(
        encrypted_seed,
        encrypted_secret_key
      ),
      do:
        impl().decrypt_and_set_node_shared_secrets_transaction_seed(
          encrypted_seed,
          encrypted_secret_key
        )

  @impl SharedSecretsKeystoreImpl
  def decrypt_and_set_daily_nonce_seed(encrypted_seed, encrypted_secret_key, timestamp),
    do: impl().decrypt_and_set_daily_nonce_seed(encrypted_seed, encrypted_secret_key, timestamp)

  @impl SharedSecretsKeystoreImpl
  def decrypt_and_set_node_shared_secrets_network_pool_seed(
        encrypted_seed,
        encrypted_secret
      ),
      do:
        impl().decrypt_and_set_node_shared_secrets_network_pool_seed(
          encrypted_seed,
          encrypted_secret
        )

  defp impl do
    Application.get_env(:uniris, __MODULE__, impl: @default_impl)
    |> Keyword.fetch!(:impl)
  end
end
