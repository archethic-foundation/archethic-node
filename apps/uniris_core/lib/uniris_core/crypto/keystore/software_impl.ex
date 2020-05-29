defmodule UnirisCore.Crypto.SoftwareKeystore do
  @moduledoc false

  use GenServer

  alias UnirisCore.Crypto, as: Crypto

  require Logger

  @behaviour UnirisCore.Crypto.KeystoreImpl

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    node_seed =
      :uniris_core
      |> Application.get_env(__MODULE__)
      |> Keyword.fetch!(:seed)

    initial_data = %{
      node_seed: node_seed,
      node_key_counter: 0,
      node_shared_key_counter: 0
    }

    case File.read(storage_nonce_file()) do
      {:ok, storage_nonce} ->
        {:ok, Map.put(initial_data, :storage_nonce, storage_nonce)}

      _ ->
        {:ok, initial_data}
    end
  end

  defp storage_nonce_file() do
    Application.app_dir(:uniris_core, "priv/crypto/storage_nonce")
  end

  @impl true
  def handle_call(
        {:sign_with_node_key, data},
        _,
        state = %{node_key_counter: index, node_seed: seed}
      ) do
    {_, pv} = previous_keypair(seed, index)
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call({:sign_with_node_key, data, index}, _, state = %{node_seed: seed}) do
    {_, pv} = Crypto.derivate_keypair(seed, index)
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call(
        {:sign_with_node_shared_key, data},
        _,
        state = %{node_secrets_transaction_seed: seed, node_shared_key_counter: index}
      ) do
    {_, pv} = previous_keypair(seed, index)
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call(
        {:sign_with_node_shared_key, data, index},
        _,
        state = %{node_secrets_transaction_seed: seed}
      ) do
    {_, pv} = Crypto.derivate_keypair(seed, index)
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call({:hash_with_daily_nonce, data}, _, state = %{daily_nonce_keys: {_, pv}}) do
    {:reply, Crypto.hash([pv, data]), state}
  end

  def handle_call({:hash_with_storage_nonce, data}, _, state = %{storage_nonce: key}) do
    {:reply, Crypto.hash([key, data]), state}
  end

  def handle_call(:node_public_key, _, state = %{node_seed: seed, node_key_counter: index}) do
    {pub, _} = previous_keypair(seed, index)
    {:reply, pub, state}
  end

  def handle_call({:node_public_key, index}, _, state = %{node_seed: seed}) do
    {pub, _} = Crypto.derivate_keypair(seed, index)
    {:reply, pub, state}
  end

  def handle_call(
        {:node_shared_secrets_public_key, index},
        _,
        state = %{node_secrets_transaction_seed: seed}
      ) do
    {pub, _} = Crypto.derivate_keypair(seed, index)
    {:reply, pub, state}
  end

  def handle_call(
        {:decrypt_with_node_key, cipher},
        _,
        state = %{node_seed: seed, node_key_counter: index}
      ) do
    try do
      {_, pv} = previous_keypair(seed, index)
      {:reply, Crypto.ec_decrypt!(cipher, pv), state}
    rescue
      _ ->
        {:reply, {:error, :decryption_failed}, state}
    end
  end

  def handle_call(
        {:decrypt_with_node_key, cipher, index},
        _,
        state = %{node_seed: seed}
      ) do
    try do
      {_, pv} = Crypto.derivate_keypair(seed, index)
      {:reply, Crypto.ec_decrypt!(cipher, pv), state}
    rescue
      _ ->
        {:reply, {:error, :decryption_failed}, state}
    end
  end

  def handle_call(
        {:derivate_beacon_chain_address, subset, date},
        _,
        state = %{storage_nonce: key}
      ) do
    {pub, _} =
      Crypto.derivate_keypair(key, Crypto.hash([subset, date]) |> :binary.decode_unsigned())

    {:reply, Crypto.hash(pub), state}
  end

  def handle_call(:number_node_keys, _from, state = %{node_key_counter: nb}) do
    {:reply, nb, state}
  end

  def handle_call(:number_node_shared_keys, _from, state = %{node_shared_key_counter: nb}) do
    {:reply, nb, state}
  end

  def handle_call({:encrypt_storage_nonce, public_key}, _from, state = %{storage_nonce: key}) do
    {:reply, Crypto.ec_encrypt(key, public_key), state}
  end

  def handle_call(
        {:encrypt_node_shared_secrets_transaction_seed, key},
        _from,
        state = %{node_secrets_transaction_seed: seed}
      ) do
    {:reply, Crypto.aes_encrypt(seed, key), state}
  end

  def handle_call(:inc_node_key_counter, _from, state) do
    new_state = Map.update!(state, :node_key_counter, &(&1 + 1))
    {:reply, :ok, new_state}
  end

  def handle_call(:inc_node_shared_key_counter, _from, state) do
    new_state = Map.update!(state, :node_shared_key_counter, &(&1 + 1))
    {:reply, :ok, new_state}
  end

  def handle_call(
        {:decrypt_and_set_daily_nonce_seed, encrypted_seed, encrypted_aes_key},
        _from,
        state = %{
          node_seed: node_seed,
          node_key_counter: index
        }
      ) do
    {_, pv} = previous_keypair(node_seed, index)
    aes_key = Crypto.ec_decrypt!(encrypted_aes_key, pv)
    daily_nonce_seed = Crypto.aes_decrypt!(encrypted_seed, aes_key)
    daily_nonce_keypair = Crypto.generate_deterministic_keypair(daily_nonce_seed)
    {:reply, :ok, Map.put(state, :daily_nonce_keys, daily_nonce_keypair)}
  end

  def handle_call(
        {:decrypt_and_set_storage_nonce, encrypted_nonce},
        _from,
        state = %{
          node_seed: node_seed,
          node_key_counter: index
        }
      ) do
    {_, pv} = previous_keypair(node_seed, index)
    storage_nonce = Crypto.ec_decrypt!(encrypted_nonce, pv)
    File.write(storage_nonce_file(), storage_nonce, [:write])
    {:reply, :ok, Map.put(state, :storage_nonce, storage_nonce)}
  end

  def handle_call(
        {:decrypt_and_set_node_shared_secrets_transaction_seed, encrypted_seed,
         encrypted_aes_key},
        _from,
        state = %{
          node_seed: node_seed,
          node_key_counter: index
        }
      ) do
    {_, pv} = previous_keypair(node_seed, index)
    aes_key = Crypto.ec_decrypt!(encrypted_aes_key, pv)
    transaction_seed = Crypto.aes_decrypt!(encrypted_seed, aes_key)

    {:reply, :ok, Map.put(state, :node_secrets_transaction_seed, transaction_seed)}
  end

  defp previous_keypair(seed, 0) do
    Crypto.derivate_keypair(seed, 0)
  end

  defp previous_keypair(seed, index) do
    Crypto.derivate_keypair(seed, index - 1)
  end

  @impl true
  def sign_with_node_key(data) do
    GenServer.call(__MODULE__, {:sign_with_node_key, data})
  end

  @impl true
  def sign_with_node_key(data, index) do
    GenServer.call(__MODULE__, {:sign_with_node_key, data, index})
  end

  @impl true
  def sign_with_node_shared_secrets_key(data) do
    GenServer.call(__MODULE__, {:sign_with_node_shared_key, data})
  end

  @impl true
  def sign_with_node_shared_secrets_key(data, index) do
    GenServer.call(__MODULE__, {:sign_with_node_shared_key, data, index})
  end

  @impl true
  def hash_with_daily_nonce(data) do
    GenServer.call(__MODULE__, {:hash_with_daily_nonce, data})
  end

  @impl true
  def hash_with_storage_nonce(data) do
    GenServer.call(__MODULE__, {:hash_with_storage_nonce, data})
  end

  @impl true
  def decrypt_and_set_daily_nonce_seed(encrypted_seed, encrypted_aes_key) do
    GenServer.call(
      __MODULE__,
      {:decrypt_and_set_daily_nonce_seed, encrypted_seed, encrypted_aes_key}
    )
  end

  @impl true
  def decrypt_and_set_storage_nonce(encrypted_nonce) do
    GenServer.call(
      __MODULE__,
      {:decrypt_and_set_storage_nonce, encrypted_nonce}
    )
  end

  @impl true
  def decrypt_and_set_node_shared_secrets_transaction_seed(encrypted_seed, encrypted_aes_key) do
    GenServer.call(
      __MODULE__,
      {:decrypt_and_set_node_shared_secrets_transaction_seed, encrypted_seed, encrypted_aes_key}
    )
  end

  @impl true
  def node_public_key() do
    GenServer.call(__MODULE__, :node_public_key)
  end

  @impl true
  def node_public_key(index) do
    GenServer.call(__MODULE__, {:node_public_key, index})
  end

  @impl true
  def node_shared_secrets_public_key(index) do
    GenServer.call(__MODULE__, {:node_shared_secrets_public_key, index})
  end

  @impl true
  def increment_number_of_generate_node_keys() do
    GenServer.call(__MODULE__, :inc_node_key_counter)
  end

  @impl true
  def increment_number_of_generate_node_shared_secrets_keys() do
    GenServer.call(__MODULE__, :inc_node_shared_key_counter)
  end

  @impl true
  def decrypt_with_node_key!(cipher) do
    case GenServer.call(__MODULE__, {:decrypt_with_node_key, cipher}) do
      {:error, :decryption_failed} ->
        raise "Decryption failed"

      result ->
        result
    end
  end

  @impl true
  def decrypt_with_node_key!(cipher, index) do
    case GenServer.call(__MODULE__, {:decrypt_with_node_key, cipher, index}) do
      {:error, :decryption_failed} ->
        raise "Decryption failed"

      result ->
        result
    end
  end

  @impl true
  def derivate_beacon_chain_address(subset, date) do
    GenServer.call(__MODULE__, {:derivate_beacon_chain_address, subset, date})
  end

  @impl true
  def number_of_node_keys() do
    GenServer.call(__MODULE__, :number_node_keys)
  end

  @impl true
  def number_of_node_shared_secrets_keys() do
    GenServer.call(__MODULE__, :number_node_shared_keys)
  end

  @impl true
  def encrypt_storage_nonce(public_key) do
    GenServer.call(__MODULE__, {:encrypt_storage_nonce, public_key})
  end

  @impl true
  def encrypt_node_shared_secrets_transaction_seed(key) do
    GenServer.call(__MODULE__, {:encrypt_node_shared_secrets_transaction_seed, key})
  end
end
