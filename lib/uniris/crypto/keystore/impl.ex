defmodule Uniris.Crypto.KeystoreImpl do
  @moduledoc false

  alias Uniris.Crypto

  @callback child_spec(any()) :: Supervisor.child_spec()

  @callback sign_with_node_key(data :: binary()) :: binary()
  @callback sign_with_node_key(data :: binary(), index :: non_neg_integer()) :: binary()
  @callback sign_with_node_shared_secrets_key(data :: binary()) :: binary()
  @callback sign_with_node_shared_secrets_key(data :: binary(), index :: non_neg_integer()) ::
              binary()
  @callback sign_with_network_pool_key(data :: binary()) :: binary()
  @callback sign_with_network_pool_key(data :: binary(), index :: non_neg_integer()) :: binary()

  @callback hash_with_daily_nonce(data :: iodata()) :: binary()

  @callback node_public_key() :: Crypto.key()
  @callback node_public_key(index :: number()) :: Crypto.key()
  @callback node_shared_secrets_public_key(index :: non_neg_integer()) :: Crypto.key()
  @callback network_pool_public_key(index :: non_neg_integer()) :: Crypto.key()

  @callback increment_number_of_generate_node_keys() :: :ok
  @callback increment_number_of_generate_node_shared_secrets_keys() :: :ok
  @callback increment_number_of_generate_network_pool_keys() :: :ok

  @callback decrypt_with_node_key!(cipher :: binary()) :: term()
  @callback decrypt_with_node_key!(cipher :: binary(), index :: non_neg_integer()) :: term()

  @callback number_of_node_keys() :: index :: non_neg_integer()
  @callback number_of_node_shared_secrets_keys() :: non_neg_integer()
  @callback number_of_network_pool_keys() :: non_neg_integer()

  @callback encrypt_node_shared_secrets_transaction_seed(key :: binary()) :: binary()
  @callback decrypt_and_set_node_shared_secrets_transaction_seed(
              encrypted_seed :: binary(),
              encrypted_secret_key :: binary()
            ) :: :ok

  @callback decrypt_and_set_daily_nonce_seed(
              encrypted_seed :: binary(),
              encrypted_secret_key :: binary()
            ) :: :ok

  @callback encrypt_network_pool_seed(key :: binary()) :: binary()
  @callback decrypt_and_set_node_shared_secrets_network_pool_seed(
              encrypted_seed :: binary(),
              encrypted_secret_key :: binary()
            ) :: :ok
end
