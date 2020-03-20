defmodule UnirisCrypto.Keystore do
  @moduledoc false

  @behaviour __MODULE__.Impl

  alias __MODULE__.SoftwareImpl

  @keystore_impl Application.get_env(:uniris_crypto, :keystore_impl, SoftwareImpl)

  defdelegate child_spec(opts), to: @keystore_impl

  @impl true
  @spec sign_with_node_key(data :: binary()) :: binary()
  def sign_with_node_key(data) do
    @keystore_impl.sign_with_node_key(data)
  end

  @impl true
  @spec sign_with_node_key(data :: binary(), index :: number()) :: binary()
  def sign_with_node_key(data, index) do
    @keystore_impl.sign_with_node_key(data, index)
  end

  @impl true
  @spec sign_with_origin_key(data :: binary()) :: binary()
  def sign_with_origin_key(data) do
    @keystore_impl.sign_with_origin_key(data)
  end

  @impl true
  @spec origin_public_keys() :: list(UnirisCrypto.key())
  def origin_public_keys() do
    @keystore_impl.origin_public_keys()
  end

  @impl true
  @spec hash_with_daily_nonce(data :: binary()) :: binary()
  def hash_with_daily_nonce(data) do
    @keystore_impl.hash_with_daily_nonce(data)
  end

  @impl true
  @spec hash_with_storage_nonce(data :: binary()) :: binary()
  def hash_with_storage_nonce(data) do
    @keystore_impl.hash_with_storage_nonce(data)
  end

  @impl true
  @spec add_origin_seed(seed :: binary()) :: :ok
  def add_origin_seed(seed) do
    @keystore_impl.add_origin_seed(seed)
  end

  @impl true
  @spec set_daily_nonce(seed :: binary()) :: :ok
  def set_daily_nonce(seed) do
    @keystore_impl.set_daily_nonce(seed)
  end

  @impl true
  @spec set_storage_nonce(seed :: binary()) :: :ok
  def set_storage_nonce(seed) do
    @keystore_impl.set_storage_nonce(seed)
  end

  @impl true
  @spec node_public_key() :: UnirisCrypto.key()
  def node_public_key() do
    @keystore_impl.node_public_key()
  end

  @impl true
  @spec node_public_key(index :: number()) :: UnirisCyrpto.key()
  def node_public_key(index) do
    @keystore_impl.node_public_key(index)
  end

  @impl true
  @spec increment_number_of_generate_node_keys() :: :ok
  def increment_number_of_generate_node_keys() do
    @keystore_impl.increment_number_of_generate_node_keys()
  end

  @impl true
  @spec decrypt_with_node_key!(binary()) :: :ok
  def decrypt_with_node_key!(cipher) do
    @keystore_impl.decrypt_with_node_key!(cipher)
  end

  @impl true
  def derivate_beacon_chain_address(subset, date) do
    @keystore_impl.derivate_beacon_chain_address(subset, date)
  end

end
