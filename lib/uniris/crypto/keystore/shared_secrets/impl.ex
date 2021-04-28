defmodule Uniris.Crypto.SharedSecretsKeystoreImpl do
  @moduledoc false

  alias Uniris.Crypto

  @callback sign_with_node_shared_secrets_key(data :: binary()) :: binary()
  @callback sign_with_node_shared_secrets_key(data :: binary(), index :: non_neg_integer()) ::
              binary()
  @callback sign_with_network_pool_key(data :: binary()) :: binary()
  @callback sign_with_network_pool_key(data :: binary(), index :: non_neg_integer()) :: binary()
  @callback sign_with_daily_nonce_key(data :: binary(), DateTime.t()) :: binary()

  @callback node_shared_secrets_public_key(index :: non_neg_integer()) :: Crypto.key()
  @callback network_pool_public_key(index :: non_neg_integer()) :: Crypto.key()

  @callback encrypt_node_shared_secrets_transaction_seed(key :: binary()) :: binary()
  @callback encrypt_network_pool_seed(key :: binary()) :: binary()

  @callback decrypt_and_set_node_shared_secrets_transaction_seed(
              encrypted_seed :: binary(),
              encrypted_secret_key :: binary()
            ) :: :ok | :error

  @callback decrypt_and_set_daily_nonce_seed(
              encrypted_seed :: binary(),
              encrypted_secret_key :: binary(),
              timestamp :: DateTime.t()
            ) :: :ok | :error

  @callback decrypt_and_set_node_shared_secrets_network_pool_seed(
              encrypted_seed :: binary(),
              encrypted_secret_key :: binary()
            ) :: :ok | :error
end
