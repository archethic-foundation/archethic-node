defmodule Uniris.Crypto.SharedSecretsKeystore.SoftwareImpl do
  @moduledoc false

  alias Uniris.Crypto
  alias Uniris.Crypto.KeystoreCounter
  alias Uniris.Crypto.SharedSecretsKeystoreImpl

  use GenServer

  require Logger

  @behaviour SharedSecretsKeystoreImpl

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl SharedSecretsKeystoreImpl
  @spec sign_with_node_shared_secrets_key(data :: binary()) :: binary()
  def sign_with_node_shared_secrets_key(data) do
    GenServer.call(__MODULE__, {:sign_with_node_shared_key, data})
  end

  @impl SharedSecretsKeystoreImpl
  @spec sign_with_node_shared_secrets_key(data :: binary(), index :: non_neg_integer()) ::
          binary()
  def sign_with_node_shared_secrets_key(data, index) do
    GenServer.call(__MODULE__, {:sign_with_node_shared_key, data, index})
  end

  @impl SharedSecretsKeystoreImpl
  @spec sign_with_network_pool_key(data :: binary()) :: binary()
  def sign_with_network_pool_key(data) do
    GenServer.call(__MODULE__, {:sign_with_network_pool_key, data})
  end

  @impl SharedSecretsKeystoreImpl
  @spec sign_with_network_pool_key(data :: binary(), index :: non_neg_integer()) :: binary()
  def sign_with_network_pool_key(data, index) do
    GenServer.call(__MODULE__, {:sign_with_network_pool_key, data, index})
  end

  @impl SharedSecretsKeystoreImpl
  @spec sign_with_daily_nonce_key(data :: binary(), DateTime.t()) :: binary()
  def sign_with_daily_nonce_key(data, index) do
    GenServer.call(__MODULE__, {:sign_with_daily_nonce_key, data, index})
  end

  @impl SharedSecretsKeystoreImpl
  @spec node_shared_secrets_public_key(index :: non_neg_integer()) :: Crypto.key()
  def node_shared_secrets_public_key(index) do
    GenServer.call(__MODULE__, {:node_shared_secrets_public_key, index})
  end

  @impl SharedSecretsKeystoreImpl
  @spec network_pool_public_key(index :: non_neg_integer()) :: Crypto.key()
  def network_pool_public_key(index) do
    GenServer.call(__MODULE__, {:network_pool_public_key, index})
  end

  @impl SharedSecretsKeystoreImpl
  @spec encrypt_node_shared_secrets_transaction_seed(key :: binary()) :: binary()
  def encrypt_node_shared_secrets_transaction_seed(key) do
    GenServer.call(__MODULE__, {:encrypt_node_shared_secrets_transaction_seed, key})
  end

  @impl SharedSecretsKeystoreImpl
  @spec encrypt_network_pool_seed(key :: binary()) :: binary()
  def encrypt_network_pool_seed(key) do
    GenServer.call(__MODULE__, {:encrypt_network_pool_transaction_seed, key})
  end

  @impl SharedSecretsKeystoreImpl
  @spec decrypt_and_set_node_shared_secrets_transaction_seed(
          encrypted_seed :: binary(),
          encrypted_secret_key :: binary()
        ) :: :ok
  def decrypt_and_set_node_shared_secrets_transaction_seed(encrypted_seed, encrypted_secret_key) do
    GenServer.call(
      __MODULE__,
      {:decrypt_and_set_node_shared_secrets_transaction_seed, encrypted_seed,
       encrypted_secret_key}
    )
  end

  @impl SharedSecretsKeystoreImpl
  @spec decrypt_and_set_daily_nonce_seed(
          encrypted_seed :: binary(),
          encrypted_secret_key :: binary(),
          timestamp :: DateTime.t()
        ) :: :ok
  def decrypt_and_set_daily_nonce_seed(encrypted_seed, encrypted_secret_key, timestamp) do
    GenServer.call(
      __MODULE__,
      {:decrypt_and_set_daily_nonce_seed, encrypted_seed, encrypted_secret_key, timestamp}
    )
  end

  @impl SharedSecretsKeystoreImpl
  @spec decrypt_and_set_node_shared_secrets_network_pool_seed(
          encrypted_seed :: binary(),
          encrypted_secret_key :: binary()
        ) :: :ok
  def decrypt_and_set_node_shared_secrets_network_pool_seed(encrypted_seed, encrypted_secret_key) do
    GenServer.call(
      __MODULE__,
      {:decrypt_and_set_node_shared_secrets_network_pool_seed, encrypted_seed,
       encrypted_secret_key}
    )
  end

  @impl GenServer
  def init(_) do
    {:ok, %{daily_nonce_index: 0, network_pool_index: 0, daily_nonce_keys: %{}}}
  end

  @impl GenServer
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

  def handle_call(
        {:sign_with_daily_nonce_key, data, timestamp},
        _,
        state = %{daily_nonce_keys: keys}
      ) do
    {pub, pv} =
      keys
      |> Enum.sort_by(&elem(&1, 0), {:desc, DateTime})
      |> Enum.filter(&(DateTime.diff(elem(&1, 0), timestamp) <= 0))
      |> List.first()
      |> elem(1)

    Logger.debug("Sign with the daily nonce for the public key #{Base.encode16(pub)}")

    {:reply, Crypto.sign(data, pv), state}
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
        {:decrypt_and_set_daily_nonce_seed, encrypted_seed, encrypted_aes_key, timestamp},
        _from,
        state = %{
          daily_nonce_keys: daily_nonce_keys
        }
      ) do
    with {:ok, aes_key} <- Crypto.ec_decrypt_with_node_key(encrypted_aes_key),
         {:ok, daily_nonce_seed} <- Crypto.aes_decrypt(encrypted_seed, aes_key) do
      daily_nonce_keypair = Crypto.generate_deterministic_keypair(daily_nonce_seed)

      new_keys =
        daily_nonce_keys
        |> Map.put(timestamp, daily_nonce_keypair)
        |> Enum.sort_by(&elem(&1, 0), {:desc, DateTime})
        |> Enum.into(%{})

      Logger.debug(
        "Daily nonce stored for the public key: #{Base.encode16(daily_nonce_keypair |> elem(0))} "
      )

      {:reply, :ok, Map.put(state, :daily_nonce_keys, new_keys)}
    else
      {:error, :decryption_failed} ->
        Logger.error("Cannot decrypt the node shared secrets daily nonce seed")
        {:reply, :error, state}
    end
  end

  def handle_call(
        {:decrypt_and_set_node_shared_secrets_network_pool_seed, encrypted_seed,
         encrypted_aes_key},
        _from,
        state
      ) do
    with {:ok, aes_key} <- Crypto.ec_decrypt_with_node_key(encrypted_aes_key),
         {:ok, network_pool_seed} <- Crypto.aes_decrypt(encrypted_seed, aes_key) do
      {:reply, :ok, Map.put(state, :network_pool_seed, network_pool_seed)}
    else
      {:error, :decryption_failed} ->
        Logger.error("Cannot decrypt the node shared secrets network pool seed")
        {:reply, :error, state}
    end
  end

  def handle_call(
        {:decrypt_and_set_node_shared_secrets_transaction_seed, encrypted_seed,
         encrypted_aes_key},
        _from,
        state
      ) do
    with {:ok, aes_key} <- Crypto.ec_decrypt_with_node_key(encrypted_aes_key),
         {:ok, transaction_seed} <- Crypto.aes_decrypt(encrypted_seed, aes_key) do
      {:reply, :ok, Map.put(state, :node_secrets_transaction_seed, transaction_seed)}
    else
      {:error, :decryption_failed} ->
        Logger.error("Cannot decrypt the node shared secrets transaction seed")
        {:reply, :error, state}
    end
  end

  defp previous_keypair(seed, 0) do
    Crypto.derive_keypair(seed, 0)
  end

  defp previous_keypair(seed, index) do
    Crypto.derive_keypair(seed, index - 1)
  end
end
