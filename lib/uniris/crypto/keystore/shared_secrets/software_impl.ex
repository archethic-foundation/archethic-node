defmodule Uniris.Crypto.SharedSecretsKeystore.SoftwareImpl do
  @moduledoc false

  alias Uniris.Crypto
  alias Uniris.Crypto.KeystoreCounter
  alias Uniris.Crypto.SharedSecretsKeystoreImpl

  use GenStateMachine, callback_mode: :handle_event_function

  require Logger

  @behaviour SharedSecretsKeystoreImpl

  def start_link(args \\ []) do
    GenStateMachine.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl SharedSecretsKeystoreImpl
  @spec sign_with_node_shared_secrets_key(data :: binary()) :: binary()
  def sign_with_node_shared_secrets_key(data) do
    GenStateMachine.call(__MODULE__, {:sign_with_node_shared_key, data})
  end

  @impl SharedSecretsKeystoreImpl
  @spec sign_with_node_shared_secrets_key(data :: binary(), index :: non_neg_integer()) ::
          binary()
  def sign_with_node_shared_secrets_key(data, index) do
    GenStateMachine.call(__MODULE__, {:sign_with_node_shared_key, data, index})
  end

  @impl SharedSecretsKeystoreImpl
  @spec sign_with_network_pool_key(data :: binary()) :: binary()
  def sign_with_network_pool_key(data) do
    GenStateMachine.call(__MODULE__, {:sign_with_network_pool_key, data})
  end

  @impl SharedSecretsKeystoreImpl
  @spec sign_with_network_pool_key(data :: binary(), index :: non_neg_integer()) :: binary()
  def sign_with_network_pool_key(data, index) do
    GenStateMachine.call(__MODULE__, {:sign_with_network_pool_key, data, index})
  end

  @impl SharedSecretsKeystoreImpl
  @spec sign_with_daily_nonce_key(data :: binary(), DateTime.t()) :: binary()
  def sign_with_daily_nonce_key(data, index) do
    GenServer.call(__MODULE__, {:sign_with_daily_nonce_key, data, index})
  end

  @impl SharedSecretsKeystoreImpl
  @spec node_shared_secrets_public_key(index :: non_neg_integer()) :: Crypto.key()
  def node_shared_secrets_public_key(index) do
    GenStateMachine.call(__MODULE__, {:node_shared_secrets_public_key, index})
  end

  @impl SharedSecretsKeystoreImpl
  @spec network_pool_public_key(index :: non_neg_integer()) :: Crypto.key()
  def network_pool_public_key(index) do
    GenStateMachine.call(__MODULE__, {:network_pool_public_key, index})
  end

  @impl SharedSecretsKeystoreImpl
  @spec wrap_secrets(key :: binary()) ::
          {enc_transaction_seed :: binary(), enc_network_pool_seed :: binary()}
  def wrap_secrets(key) do
    GenStateMachine.call(__MODULE__, {:wrap_secrets, key})
  end

  @impl SharedSecretsKeystoreImpl
  @spec unwrap_secrets(encrypted_secrets :: binary(), encrypted_key :: binary(), DateTime.t()) ::
          :ok | :error
  def unwrap_secrets(
        secrets,
        encrypted_secret_key,
        date = %DateTime{}
      ) do
    GenStateMachine.call(__MODULE__, {:unwrap_secrets, secrets, encrypted_secret_key, date})
  end

  @impl GenStateMachine
  def init(_) do
    {:ok, :idle, %{daily_nonce_index: 0, network_pool_index: 0, daily_nonce_keys: %{}}}
  end

  @impl GenStateMachine
  def handle_event(
        {:call, from},
        {:sign_with_node_shared_key, data},
        :authorized,
        %{transaction_seed: seed}
      ) do
    index = KeystoreCounter.get_node_shared_key_counter()
    {_, pv} = previous_keypair(seed, index)
    {:keep_state_and_data, {:reply, from, Crypto.sign(data, pv)}}
  end

  def handle_event({:call, _}, {:sign_with_node_shared_key, _}, :idle, _data) do
    {:keep_state_and_data, :postpone}
  end

  def handle_event(
        {:call, from},
        {:sign_with_node_shared_key, data, index},
        :authorized,
        %{transaction_seed: seed}
      ) do
    {_, pv} = Crypto.derive_keypair(seed, index)
    {:keep_state_and_data, {:reply, from, Crypto.sign(data, pv)}}
  end

  def handle_event({:call, _}, {:sign_with_node_shared_key, _, _}, :idle, _data) do
    {:keep_state_and_data, :postpone}
  end

  def handle_event(
        {:call, from},
        {:sign_with_network_pool_key, data},
        :authorized,
        %{network_pool_seed: seed}
      ) do
    index = KeystoreCounter.get_network_pool_key_counter()
    {_, pv} = previous_keypair(seed, index)
    {:keep_state_and_data, {:reply, from, Crypto.sign(data, pv)}}
  end

  def handle_event({:call, _}, {:sign_with_network_pool_key, _}, :idle, _data) do
    {:keep_state_and_data, :postpone}
  end

  def handle_event(
        {:call, from},
        {:sign_with_network_pool_key, data, index},
        :authorized,
        %{network_pool_seed: seed}
      ) do
    {_, pv} = Crypto.derive_keypair(seed, index)
    {:keep_state_and_data, {:reply, from, Crypto.sign(data, pv)}}
  end

  def handle_event({:call, _}, {:sign_with_network_pool_key, _, _}, :idle, _data) do
    {:keep_state_and_data, :postpone}
  end

  def handle_event(
        {:call, from},
        {:sign_with_daily_nonce_key, data, timestamp},
        :authorized,
        %{daily_nonce_keys: keys}
      ) do
    {pub, pv} =
      keys
      |> Enum.sort_by(&elem(&1, 0), {:desc, DateTime})
      |> Enum.filter(&(DateTime.diff(elem(&1, 0), timestamp) <= 0))
      |> List.first()
      |> elem(1)

    Logger.debug("Sign with the daily nonce for the public key #{Base.encode16(pub)}")

    {:keep_state_and_data, {:reply, from, Crypto.sign(data, pv)}}
  end

  def handle_event({:call, _}, {:sign_with_daily_nonce_key, _, _}, :idle, _data) do
    {:keep_state_and_data, :postpone}
  end

  def handle_event(
        {:call, from},
        {:node_shared_secrets_public_key, index},
        :authorized,
        %{transaction_seed: seed}
      ) do
    {pub, _} = Crypto.derive_keypair(seed, index)
    {:keep_state_and_data, {:reply, from, pub}}
  end

  def handle_event({:call, _}, {:node_shared_secrets_public_key, _}, :idle, _data) do
    {:keep_state_and_data, :postpone}
  end

  def handle_event({:call, from}, {:network_pool_public_key, index}, :authorized, %{
        network_pool_seed: seed
      }) do
    {pub, _} = Crypto.derive_keypair(seed, index)
    {:keep_state_and_data, {:reply, from, pub}}
  end

  def handle_event({:call, _}, {:network_pool_public_key, _}, :idle, _data) do
    {:keep_state_and_data, :postpone}
  end

  def handle_event(
        {:call, from},
        {:wrap_secrets, secret_key},
        :authorized,
        %{transaction_seed: transaction_seed, network_pool_seed: network_pool_seed}
      ) do
    encrypted_transaction_seed = Crypto.aes_encrypt(transaction_seed, secret_key)
    encrypted_network_pool_seed = Crypto.aes_encrypt(network_pool_seed, secret_key)

    {:keep_state_and_data,
     {:reply, from, {encrypted_transaction_seed, encrypted_network_pool_seed}}}
  end

  def handle_event({:call, _}, {:wrap_secrets, _, _}, :idle, _data) do
    {:keep_state_and_data, :postpone}
  end

  def handle_event(
        {:call, from},
        {:unwrap_secrets, encrypted_secrets, encrypted_aes_key, timestamp},
        _,
        data = %{
          daily_nonce_keys: daily_nonce_keys
        }
      ) do
    <<enc_daily_nonce_seed::binary-size(60), enc_transaction_seed::binary-size(60),
      enc_network_pool_seed::binary-size(60)>> = encrypted_secrets

    with {:ok, aes_key} <- Crypto.ec_decrypt_with_node_key(encrypted_aes_key),
         {:ok, daily_nonce_seed} <- Crypto.aes_decrypt(enc_daily_nonce_seed, aes_key),
         {:ok, transaction_seed} <- Crypto.aes_decrypt(enc_transaction_seed, aes_key),
         {:ok, network_pool_seed} <- Crypto.aes_decrypt(enc_network_pool_seed, aes_key) do
      daily_nonce_keypair = Crypto.generate_deterministic_keypair(daily_nonce_seed)

      new_keys =
        daily_nonce_keys
        |> Map.put(timestamp, daily_nonce_keypair)
        |> Enum.sort_by(&elem(&1, 0), {:desc, DateTime})
        |> Enum.into(%{})

      Logger.debug(
        "Daily nonce stored for the public key: #{Base.encode16(daily_nonce_keypair |> elem(0))} "
      )

      new_data =
        data
        |> Map.put(:daily_nonce_keys, new_keys)
        |> Map.put(:transaction_seed, transaction_seed)
        |> Map.put(:network_pool_seed, network_pool_seed)

      {:next_state, :authorized, new_data, {:reply, from, :ok}}
    else
      {:error, :decryption_failed} ->
        Logger.error("Cannot decrypt the node shared secrets")
        {:keep_state_and_data, {:reply, from, :error}}
    end
  end

  defp previous_keypair(seed, 0) do
    Crypto.derive_keypair(seed, 0)
  end

  defp previous_keypair(seed, index) do
    Crypto.derive_keypair(seed, index - 1)
  end
end
