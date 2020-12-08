defmodule Uniris.Crypto.Keystore do
  @moduledoc false

  alias Uniris.Crypto.KeystoreImpl

  @behaviour KeystoreImpl

  @impl KeystoreImpl
  def child_spec(args) do
    impl().child_spec(args)
  end

  @impl KeystoreImpl
  @spec sign_with_node_key(data :: iolist()) :: binary()
  def sign_with_node_key(data) do
    impl().sign_with_node_key(data)
  end

  @impl KeystoreImpl
  @spec sign_with_node_key(data :: iolist(), index :: number()) :: binary()
  def sign_with_node_key(data, index) do
    impl().sign_with_node_key(data, index)
  end

  @impl KeystoreImpl
  @spec hash_with_daily_nonce(data :: iodata()) :: binary()
  def hash_with_daily_nonce(data) do
    impl().hash_with_daily_nonce(data)
  end

  @impl KeystoreImpl
  @spec node_public_key() :: Uniris.Crypto.key()
  def node_public_key do
    impl().node_public_key()
  end

  @impl KeystoreImpl
  @spec node_public_key(index :: number()) :: Uniris.Crypto.key()
  def node_public_key(index) do
    impl().node_public_key(index)
  end

  @impl KeystoreImpl
  @spec increment_number_of_generate_node_keys() :: :ok
  def increment_number_of_generate_node_keys do
    impl().increment_number_of_generate_node_keys()
  end

  @impl KeystoreImpl
  @spec increment_number_of_generate_node_shared_secrets_keys() :: :ok
  def increment_number_of_generate_node_shared_secrets_keys do
    impl().increment_number_of_generate_node_shared_secrets_keys()
  end

  @impl KeystoreImpl
  @spec decrypt_with_node_key!(binary()) :: term()
  def decrypt_with_node_key!(cipher) when is_binary(cipher) do
    impl().decrypt_with_node_key!(cipher)
  end

  @impl KeystoreImpl
  @spec decrypt_with_node_key!(binary(), non_neg_integer()) :: term()
  def decrypt_with_node_key!(cipher, index) do
    impl().decrypt_with_node_key!(cipher, index)
  end

  @impl KeystoreImpl
  @spec number_of_node_keys() :: non_neg_integer()
  def number_of_node_keys do
    impl().number_of_node_keys()
  end

  @impl KeystoreImpl
  @spec number_of_node_shared_secrets_keys() :: non_neg_integer()
  def number_of_node_shared_secrets_keys do
    impl().number_of_node_shared_secrets_keys()
  end

  @impl KeystoreImpl
  @spec sign_with_node_shared_secrets_key(data :: iolist()) :: binary()
  def sign_with_node_shared_secrets_key(data) do
    impl().sign_with_node_shared_secrets_key(data)
  end

  @impl KeystoreImpl
  @spec sign_with_node_shared_secrets_key(data :: iolist(), index :: number()) :: binary()
  def sign_with_node_shared_secrets_key(data, index) do
    impl().sign_with_node_shared_secrets_key(data, index)
  end

  @impl KeystoreImpl
  @spec decrypt_and_set_node_shared_secrets_transaction_seed(
          encrypted_seed :: binary(),
          encrypted_secret_key :: binary()
        ) :: :ok
  def decrypt_and_set_node_shared_secrets_transaction_seed(encrypted_seed, encrypted_secret_key) do
    impl().decrypt_and_set_node_shared_secrets_transaction_seed(
      encrypted_seed,
      encrypted_secret_key
    )
  end

  @impl KeystoreImpl
  @callback node_shared_secrets_public_key(index :: non_neg_integer()) :: Uniris.Crypto.key()
  def node_shared_secrets_public_key(index) do
    impl().node_shared_secrets_public_key(index)
  end

  @impl KeystoreImpl
  @spec decrypt_and_set_daily_nonce_seed(
          encrypted_seed :: binary(),
          encrypted_secret_key :: binary()
        ) :: :ok
  def decrypt_and_set_daily_nonce_seed(encrypted_seed, encrypted_secret_key) do
    impl().decrypt_and_set_daily_nonce_seed(encrypted_seed, encrypted_secret_key)
  end

  @impl KeystoreImpl
  @spec encrypt_node_shared_secrets_transaction_seed(key :: binary()) :: binary()
  def encrypt_node_shared_secrets_transaction_seed(key) do
    impl().encrypt_node_shared_secrets_transaction_seed(key)
  end

  @impl KeystoreImpl
  @spec decrypt_and_set_node_shared_secrets_network_pool_seed(
          encrypted_seed :: binary(),
          encrypted_secret_key :: binary()
        ) :: :ok
  def decrypt_and_set_node_shared_secrets_network_pool_seed(encrypted_seed, encrypted_secret_key) do
    impl().decrypt_and_set_node_shared_secrets_network_pool_seed(
      encrypted_seed,
      encrypted_secret_key
    )
  end

  defp impl do
    Application.get_env(:uniris, __MODULE__) |> Keyword.fetch!(:impl)
  end
end
