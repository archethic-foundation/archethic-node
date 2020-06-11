defmodule UnirisCore.Crypto.Keystore do
  @moduledoc false

  @behaviour UnirisCore.Crypto.KeystoreImpl

  @default_impl UnirisCore.Crypto.SoftwareKeystore
  defdelegate child_spec(opts), to: @default_impl

  @impl true
  @spec sign_with_node_key(data :: binary()) :: binary()
  def sign_with_node_key(data) do
    impl().sign_with_node_key(data)
  end

  @impl true
  @spec sign_with_node_key(data :: binary(), index :: number()) :: binary()
  def sign_with_node_key(data, index) do
    impl().sign_with_node_key(data, index)
  end

  @impl true
  @spec hash_with_daily_nonce(data :: binary()) :: binary()
  def hash_with_daily_nonce(data) do
    impl().hash_with_daily_nonce(data)
  end

  @impl true
  @spec hash_with_storage_nonce(data :: binary()) :: binary()
  def hash_with_storage_nonce(data) do
    impl().hash_with_storage_nonce(data)
  end

  @impl true
  @spec node_public_key() :: UnirisCrypto.key()
  def node_public_key() do
    impl().node_public_key()
  end

  @impl true
  @spec node_public_key(index :: number()) :: UnirisCyrpto.key()
  def node_public_key(index) do
    impl().node_public_key(index)
  end

  @impl true
  @spec increment_number_of_generate_node_keys() :: :ok
  def increment_number_of_generate_node_keys() do
    impl().increment_number_of_generate_node_keys()
  end

  @impl true
  @spec increment_number_of_generate_node_shared_secrets_keys() :: :ok
  def increment_number_of_generate_node_shared_secrets_keys() do
    impl().increment_number_of_generate_node_shared_secrets_keys()
  end

  @impl true
  @spec decrypt_with_node_key!(binary()) :: term()
  def decrypt_with_node_key!(cipher) do
    impl().decrypt_with_node_key!(cipher)
  end

  @impl true
  @spec decrypt_with_node_key!(binary()) :: term()
  def decrypt_with_node_key!(cipher, index) do
    impl().decrypt_with_node_key!(cipher, index)
  end

  @impl true
  @spec derivate_beacon_chain_address(binary(), integer()) :: binary()
  def derivate_beacon_chain_address(subset, date) do
    impl().derivate_beacon_chain_address(subset, date)
  end

  @impl true
  @spec number_of_node_keys() :: non_neg_integer()
  def number_of_node_keys() do
    impl().number_of_node_keys()
  end

  @impl true
  @spec number_of_node_shared_secrets_keys() :: non_neg_integer()
  def number_of_node_shared_secrets_keys() do
    impl().number_of_node_shared_secrets_keys()
  end

  @impl true
  @spec sign_with_node_shared_secrets_key(data :: binary()) :: binary()
  def sign_with_node_shared_secrets_key(data) do
    impl().sign_with_node_shared_secrets_key(data)
  end

  @impl true
  @spec sign_with_node_shared_secrets_key(data :: binary(), index :: number()) :: binary()
  def sign_with_node_shared_secrets_key(data, index) do
    impl().sign_with_node_shared_secrets_key(data, index)
  end

  @impl true
  @spec decrypt_and_set_node_shared_secrets_transaction_seed(
          encrypted_seed :: binary(),
          encrypted_aes_key :: binary()
        ) :: :ok
  def decrypt_and_set_node_shared_secrets_transaction_seed(encrypted_seed, encrypted_aes_key) do
    impl().decrypt_and_set_node_shared_secrets_transaction_seed(
      encrypted_seed,
      encrypted_aes_key
    )
  end

  @impl true
  @callback node_shared_secrets_public_key(index :: number()) :: UnirisCrypto.key()
  def node_shared_secrets_public_key(index) do
    impl().node_shared_secrets_public_key(index)
  end

  @impl true
  @spec decrypt_and_set_daily_nonce_seed(
          encrypted_seed :: binary(),
          encrypted_aes_key :: binary()
        ) :: :ok
  def decrypt_and_set_daily_nonce_seed(encrypted_seed, encrypted_aes_key) do
    impl().decrypt_and_set_daily_nonce_seed(encrypted_seed, encrypted_aes_key)
  end

  @impl true
  @spec decrypt_and_set_storage_nonce(encrypted_nonce :: binary()) :: :ok
  def decrypt_and_set_storage_nonce(encrypted_nonce) do
    impl().decrypt_and_set_storage_nonce(encrypted_nonce)
  end

  @impl true
  @spec encrypt_storage_nonce(UnirisCrypto.key()) :: binary()
  def encrypt_storage_nonce(public_key) do
    impl().encrypt_storage_nonce(public_key)
  end

  @impl true
  @spec encrypt_node_shared_secrets_transaction_seed(key :: binary()) :: binary()
  def encrypt_node_shared_secrets_transaction_seed(key) do
    impl().encrypt_node_shared_secrets_transaction_seed(key)
  end

  @impl true
  @spec decrypt_and_set_node_shared_secrets_network_pool_seed(
          encrypted_seed :: binary(),
          encrypted_aes_key :: binary()
        ) :: :ok
  def decrypt_and_set_node_shared_secrets_network_pool_seed(encrypted_seed, encrypted_aes_key) do
    impl().decrypt_and_set_node_shared_secrets_network_pool_seed(
      encrypted_seed,
      encrypted_aes_key
    )
  end

  defp impl() do
    :uniris_core
    |> Application.get_env(UnirisCore.Crypto,
      keystore: @default_impl
    )
    |> Keyword.fetch!(:keystore)
  end
end
