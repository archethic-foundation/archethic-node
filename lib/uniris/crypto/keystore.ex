defmodule Uniris.Crypto.Keystore do
  @moduledoc false

  @behaviour Uniris.Crypto.KeystoreImpl

  @impl true
  def child_spec(args) do
    impl().child_spec(args)
  end

  @impl true
  @spec sign_with_node_key(data :: binary()) :: binary()
  def sign_with_node_key(data) when is_binary(data) do
    impl().sign_with_node_key(data)
  end

  @impl true
  @spec sign_with_node_key(data :: binary(), index :: number()) :: binary()
  def sign_with_node_key(data, index) when is_binary(data) and is_integer(index) and index >= 0 do
    impl().sign_with_node_key(data, index)
  end

  @impl true
  @spec hash_with_daily_nonce(data :: iodata()) :: binary()
  def hash_with_daily_nonce(data) when is_list(data) or is_binary(data) do
    impl().hash_with_daily_nonce(data)
  end

  @impl true
  @spec node_public_key() :: UnirisCrypto.key()
  def node_public_key do
    impl().node_public_key()
  end

  @impl true
  @spec node_public_key(index :: number()) :: UnirisCyrpto.key()
  def node_public_key(index) when is_integer(index) and index >= 0 do
    impl().node_public_key(index)
  end

  @impl true
  @spec increment_number_of_generate_node_keys() :: :ok
  def increment_number_of_generate_node_keys do
    impl().increment_number_of_generate_node_keys()
  end

  @impl true
  @spec increment_number_of_generate_node_shared_secrets_keys() :: :ok
  def increment_number_of_generate_node_shared_secrets_keys do
    impl().increment_number_of_generate_node_shared_secrets_keys()
  end

  @impl true
  @spec decrypt_with_node_key!(binary()) :: term()
  def decrypt_with_node_key!(cipher) when is_binary(cipher) do
    impl().decrypt_with_node_key!(cipher)
  end

  @impl true
  @spec decrypt_with_node_key!(binary()) :: term()
  def decrypt_with_node_key!(cipher, index)
      when is_binary(cipher) and is_integer(index) and index >= 0 do
    impl().decrypt_with_node_key!(cipher, index)
  end

  @impl true
  @spec number_of_node_keys() :: non_neg_integer()
  def number_of_node_keys do
    impl().number_of_node_keys()
  end

  @impl true
  @spec number_of_node_shared_secrets_keys() :: non_neg_integer()
  def number_of_node_shared_secrets_keys do
    impl().number_of_node_shared_secrets_keys()
  end

  @impl true
  @spec sign_with_node_shared_secrets_key(data :: binary()) :: binary()
  def sign_with_node_shared_secrets_key(data) when is_binary(data) do
    impl().sign_with_node_shared_secrets_key(data)
  end

  @impl true
  @spec sign_with_node_shared_secrets_key(data :: binary(), index :: number()) :: binary()
  def sign_with_node_shared_secrets_key(data, index)
      when is_binary(data) and is_integer(index) and index >= 0 do
    impl().sign_with_node_shared_secrets_key(data, index)
  end

  @impl true
  @spec decrypt_and_set_node_shared_secrets_transaction_seed(
          encrypted_seed :: binary(),
          encrypted_aes_key :: binary()
        ) :: :ok
  def decrypt_and_set_node_shared_secrets_transaction_seed(encrypted_seed, encrypted_aes_key)
      when is_binary(encrypted_seed) and is_binary(encrypted_aes_key) do
    impl().decrypt_and_set_node_shared_secrets_transaction_seed(
      encrypted_seed,
      encrypted_aes_key
    )
  end

  @impl true
  @callback node_shared_secrets_public_key(index :: non_neg_integer()) :: UnirisCrypto.key()
  def node_shared_secrets_public_key(index) when is_integer(index) and index >= 0 do
    impl().node_shared_secrets_public_key(index)
  end

  @impl true
  @spec decrypt_and_set_daily_nonce_seed(
          encrypted_seed :: binary(),
          encrypted_aes_key :: binary()
        ) :: :ok
  def decrypt_and_set_daily_nonce_seed(encrypted_seed, encrypted_aes_key)
      when is_binary(encrypted_seed) and is_binary(encrypted_aes_key) do
    impl().decrypt_and_set_daily_nonce_seed(encrypted_seed, encrypted_aes_key)
  end

  @impl true
  @spec encrypt_node_shared_secrets_transaction_seed(key :: binary()) :: binary()
  def encrypt_node_shared_secrets_transaction_seed(key) when is_binary(key) do
    impl().encrypt_node_shared_secrets_transaction_seed(key)
  end

  @impl true
  @spec decrypt_and_set_node_shared_secrets_network_pool_seed(
          encrypted_seed :: binary(),
          encrypted_aes_key :: binary()
        ) :: :ok
  def decrypt_and_set_node_shared_secrets_network_pool_seed(encrypted_seed, encrypted_aes_key)
      when is_binary(encrypted_seed) and is_binary(encrypted_aes_key) do
    impl().decrypt_and_set_node_shared_secrets_network_pool_seed(
      encrypted_seed,
      encrypted_aes_key
    )
  end

  defp impl do
    Application.get_env(:uniris, __MODULE__) |> Keyword.fetch!(:impl)
  end
end
