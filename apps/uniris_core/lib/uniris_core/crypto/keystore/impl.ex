defmodule UnirisCore.Crypto.KeystoreImpl do
  @moduledoc false

  @callback sign_with_node_key(data :: binary()) :: binary()
  @callback sign_with_node_key(data :: binary(), index :: number()) :: binary()
  @callback sign_with_node_shared_secrets_key(data :: binary()) :: binary()
  @callback sign_with_node_shared_secrets_key(data :: binary(), index :: number()) :: binary()
  @callback hash_with_daily_nonce(data :: binary()) :: binary()
  @callback hash_with_storage_nonce(data :: binary()) :: binary()
  @callback node_public_key() :: UnirisCore.Crypto.key()
  @callback node_public_key(index :: number()) :: UnirisCyrpto.key()
  @callback node_shared_secrets_public_key(index :: number()) :: UnirisCore.Crypto.key()
  @callback increment_number_of_generate_node_keys() :: :ok
  @callback increment_number_of_generate_node_shared_secrets_keys() :: :ok
  @callback decrypt_with_node_key!(cipher :: binary()) :: term()
  @callback decrypt_with_node_key!(cipher :: binary(), index :: non_neg_integer()) :: term()
  @callback derivate_beacon_chain_address(subset :: binary(), date :: non_neg_integer()) ::
              UnirisCore.Crypto.key()
  @callback number_of_node_keys() :: index :: non_neg_integer()
  @callback number_of_node_shared_secrets_keys() :: non_neg_integer()

  @callback encrypt_node_shared_secrets_transaction_seed(key :: binary()) :: binary()
  @callback decrypt_and_set_node_shared_secrets_transaction_seed(
              encrypted_seed :: binary(),
              encrypted_aes_key :: binary()
            ) :: :ok

  @callback decrypt_and_set_daily_nonce_seed(
              encrypted_seed :: binary(),
              encrypted_aes_key :: binary()
            ) :: :ok

  @callback decrypt_and_set_storage_nonce(encrypted_nonce :: binary()) :: :ok
  @callback encrypt_storage_nonce(public_key :: UnirisCore.Crypto.key()) :: binary()
end
