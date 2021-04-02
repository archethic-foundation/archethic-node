defmodule Uniris.Crypto.SoftwareKeystore do
  @moduledoc false

  use GenServer

  alias Uniris.Crypto
  alias Uniris.Crypto.KeystoreCounter
  alias Uniris.Crypto.KeystoreImpl

  require Logger

  @behaviour KeystoreImpl

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    seed = Keyword.get(opts, :seed)
    {:ok, %{node_seed: seed}}
  end

  @impl GenServer
  def handle_call(
        {:sign_with_node_key, data},
        _,
        state = %{node_seed: seed}
      ) do
    index = KeystoreCounter.get_node_key_counter()
    {_, pv} = previous_keypair(seed, index)
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call({:sign_with_node_key, data, index}, _, state = %{node_seed: seed}) do
    {_, pv} = Crypto.derive_keypair(seed, index)
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call(
        {:sign_with_node_shared_key, data},
        _,
        state = %{node_secrets_transaction_seed: seed}
      ) do
    index = KeystoreCounter.get_node_shared_key_counter()
    {_, pv} = previous_keypair(seed, index)
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call(
        {:sign_with_node_shared_key, data, index},
        _,
        state = %{node_secrets_transaction_seed: seed}
      ) do
    {_, pv} = Crypto.derive_keypair(seed, index)
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call(
        {:sign_with_network_pool_key, data},
        _,
        state = %{network_pool_seed: seed}
      ) do
    index = KeystoreCounter.get_network_pool_key_counter()
    {_, pv} = previous_keypair(seed, index)
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call(
        {:sign_with_network_pool_key, data, index},
        _,
        state = %{network_pool_seed: seed}
      ) do
    {_, pv} = Crypto.derive_keypair(seed, index)
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call({:hash_with_daily_nonce, data}, _, state = %{daily_nonce_keys: {_, pv}}) do
    {:reply, Crypto.hash([pv, data]), state}
  end

  def handle_call(:node_public_key, _, state = %{node_seed: seed}) do
    index = KeystoreCounter.get_node_key_counter()
    {pub, _} = previous_keypair(seed, index)
    {:reply, pub, state}
  end

  def handle_call({:node_public_key, index}, _, state = %{node_seed: seed}) do
    {pub, _} = Crypto.derive_keypair(seed, index)
    {:reply, pub, state}
  end

  def handle_call(
        {:node_shared_secrets_public_key, index},
        _,
        state = %{node_secrets_transaction_seed: seed}
      ) do
    {pub, _} = Crypto.derive_keypair(seed, index)
    {:reply, pub, state}
  end

  def handle_call({:network_pool_public_key, index}, _, state = %{network_pool_seed: seed}) do
    {pub, _} = Crypto.derive_keypair(seed, index)
    {:reply, pub, state}
  end

  def handle_call(
        {:decrypt_with_node_key, cipher},
        _,
        state = %{node_seed: seed}
      ) do
    index = KeystoreCounter.get_network_pool_key_counter()
    {_, pv} = previous_keypair(seed, index)
    {:reply, Crypto.ec_decrypt!(cipher, pv), state}
  rescue
    _ ->
      {:reply, {:error, :decryption_failed}, state}
  end

  def handle_call(
        {:decrypt_with_node_key, cipher, index},
        _,
        state = %{node_seed: seed}
      ) do
    {_, pv} = Crypto.derive_keypair(seed, index)
    {:reply, Crypto.ec_decrypt!(cipher, pv), state}
  rescue
    _ ->
      {:reply, {:error, :decryption_failed}, state}
  end

  def handle_call(
        {:encrypt_node_shared_secrets_transaction_seed, key},
        _from,
        state = %{node_secrets_transaction_seed: seed}
      ) do
    {:reply, Crypto.aes_encrypt(seed, key), state}
  end

  def handle_call(
        {:encrypt_network_pool_transaction_seed, key},
        _from,
        state = %{network_pool_seed: seed}
      ) do
    {:reply, Crypto.aes_encrypt(seed, key), state}
  end

  def handle_call(
        {:decrypt_and_set_daily_nonce_seed, encrypted_seed, encrypted_aes_key},
        _from,
        state = %{
          node_seed: node_seed
        }
      ) do
    index = KeystoreCounter.get_node_key_counter()
    {_, pv} = previous_keypair(node_seed, index)
    aes_key = Crypto.ec_decrypt!(encrypted_aes_key, pv)
    daily_nonce_seed = Crypto.aes_decrypt!(encrypted_seed, aes_key)
    daily_nonce_keypair = Crypto.generate_deterministic_keypair(daily_nonce_seed)
    {:reply, :ok, Map.put(state, :daily_nonce_keys, daily_nonce_keypair)}
  end

  def handle_call(
        {:decrypt_and_set_node_shared_secrets_network_pool_seed, encrypted_seed,
         encrypted_aes_key},
        _from,
        state = %{node_seed: node_seed}
      ) do
    index = KeystoreCounter.get_node_key_counter()
    {_, pv} = previous_keypair(node_seed, index)
    aes_key = Crypto.ec_decrypt!(encrypted_aes_key, pv)
    network_pool_seed = Crypto.aes_decrypt!(encrypted_seed, aes_key)
    {:reply, :ok, Map.put(state, :network_pool_seed, network_pool_seed)}
  end

  def handle_call(
        {:decrypt_and_set_node_shared_secrets_transaction_seed, encrypted_seed,
         encrypted_secret_key},
        _from,
        state = %{
          node_seed: node_seed
        }
      ) do
    index = KeystoreCounter.get_node_key_counter()
    {_, pv} = previous_keypair(node_seed, index)
    aes_key = Crypto.ec_decrypt!(encrypted_secret_key, pv)
    transaction_seed = Crypto.aes_decrypt!(encrypted_seed, aes_key)

    {:reply, :ok, Map.put(state, :node_secrets_transaction_seed, transaction_seed)}
  end

  defp previous_keypair(seed, 0) do
    Crypto.derive_keypair(seed, 0)
  end

  defp previous_keypair(seed, index) do
    Crypto.derive_keypair(seed, index - 1)
  end

  @impl KeystoreImpl
  def sign_with_node_key(data) do
    GenServer.call(__MODULE__, {:sign_with_node_key, data})
  end

  @impl KeystoreImpl
  def sign_with_node_key(data, index) do
    GenServer.call(__MODULE__, {:sign_with_node_key, data, index})
  end

  @impl KeystoreImpl
  def sign_with_node_shared_secrets_key(data) do
    GenServer.call(__MODULE__, {:sign_with_node_shared_key, data})
  end

  @impl KeystoreImpl
  def sign_with_node_shared_secrets_key(data, index) do
    GenServer.call(__MODULE__, {:sign_with_node_shared_key, data, index})
  end

  @impl KeystoreImpl
  def sign_with_network_pool_key(data) do
    GenServer.call(__MODULE__, {:sign_with_network_pool_key, data})
  end

  @impl KeystoreImpl
  def sign_with_network_pool_key(data, index) do
    GenServer.call(__MODULE__, {:sign_with_network_pool_key, data, index})
  end

  @impl KeystoreImpl
  def hash_with_daily_nonce(data) do
    GenServer.call(__MODULE__, {:hash_with_daily_nonce, data})
  end

  @impl KeystoreImpl
  def decrypt_and_set_daily_nonce_seed(encrypted_seed, encrypted_aes_key) do
    GenServer.call(
      __MODULE__,
      {:decrypt_and_set_daily_nonce_seed, encrypted_seed, encrypted_aes_key}
    )
  end

  @impl KeystoreImpl
  def decrypt_and_set_node_shared_secrets_transaction_seed(encrypted_seed, encrypted_aes_key) do
    GenServer.call(
      __MODULE__,
      {:decrypt_and_set_node_shared_secrets_transaction_seed, encrypted_seed, encrypted_aes_key}
    )
  end

  @impl KeystoreImpl
  def decrypt_and_set_node_shared_secrets_network_pool_seed(encrypted_seed, encrypted_secret_key) do
    GenServer.call(
      __MODULE__,
      {:decrypt_and_set_node_shared_secrets_network_pool_seed, encrypted_seed,
       encrypted_secret_key}
    )
  end

  @impl KeystoreImpl
  def node_public_key do
    GenServer.call(__MODULE__, :node_public_key)
  end

  @impl KeystoreImpl
  def node_public_key(index) do
    GenServer.call(__MODULE__, {:node_public_key, index})
  end

  @impl KeystoreImpl
  def node_shared_secrets_public_key(index) do
    GenServer.call(__MODULE__, {:node_shared_secrets_public_key, index})
  end

  @impl KeystoreImpl
  def network_pool_public_key(index) do
    GenServer.call(__MODULE__, {:network_pool_public_key, index})
  end

  @impl KeystoreImpl
  def decrypt_with_node_key!(cipher) do
    case GenServer.call(__MODULE__, {:decrypt_with_node_key, cipher}) do
      {:error, :decryption_failed} ->
        raise "Decryption failed"

      result ->
        result
    end
  end

  @impl KeystoreImpl
  def decrypt_with_node_key!(cipher, index) do
    case GenServer.call(__MODULE__, {:decrypt_with_node_key, cipher, index}) do
      {:error, :decryption_failed} ->
        raise "Decryption failed"

      result ->
        result
    end
  end

  @impl KeystoreImpl
  def encrypt_node_shared_secrets_transaction_seed(key) do
    GenServer.call(__MODULE__, {:encrypt_node_shared_secrets_transaction_seed, key})
  end

  @impl KeystoreImpl
  def encrypt_network_pool_seed(key) do
    GenServer.call(__MODULE__, {:encrypt_network_pool_transaction_seed, key})
  end
end
