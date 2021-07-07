defmodule ArchEthic.Crypto.SharedSecretsKeystore.SoftwareImpl do
  @moduledoc false

  alias ArchEthic.Crypto
  alias ArchEthic.Crypto.SharedSecretsKeystore

  alias ArchEthic.SharedSecrets

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Keys

  use GenStateMachine, callback_mode: :handle_event_function

  require Logger

  @behaviour SharedSecretsKeystore

  def start_link(args \\ []) do
    GenStateMachine.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl SharedSecretsKeystore
  @spec sign_with_node_shared_secrets_key(data :: binary()) :: binary()
  def sign_with_node_shared_secrets_key(data) do
    GenStateMachine.call(__MODULE__, {:sign_with_node_shared_key, data})
  end

  @impl SharedSecretsKeystore
  @spec sign_with_node_shared_secrets_key(data :: binary(), index :: non_neg_integer()) ::
          binary()
  def sign_with_node_shared_secrets_key(data, index) do
    GenStateMachine.call(__MODULE__, {:sign_with_node_shared_key, data, index})
  end

  @impl SharedSecretsKeystore
  @spec sign_with_network_pool_key(data :: binary()) :: binary()
  def sign_with_network_pool_key(data) do
    GenStateMachine.call(__MODULE__, {:sign_with_network_pool_key, data})
  end

  @impl SharedSecretsKeystore
  @spec sign_with_network_pool_key(data :: binary(), index :: non_neg_integer()) :: binary()
  def sign_with_network_pool_key(data, index) do
    GenStateMachine.call(__MODULE__, {:sign_with_network_pool_key, data, index})
  end

  @impl SharedSecretsKeystore
  @spec sign_with_daily_nonce_key(data :: binary(), DateTime.t()) :: binary()
  def sign_with_daily_nonce_key(data, index) do
    GenServer.call(__MODULE__, {:sign_with_daily_nonce_key, data, index})
  end

  @impl SharedSecretsKeystore
  @spec node_shared_secrets_public_key(index :: non_neg_integer()) :: Crypto.key()
  def node_shared_secrets_public_key(index) do
    GenStateMachine.call(__MODULE__, {:node_shared_secrets_public_key, index})
  end

  @impl SharedSecretsKeystore
  @spec network_pool_public_key(index :: non_neg_integer()) :: Crypto.key()
  def network_pool_public_key(index) do
    GenStateMachine.call(__MODULE__, {:network_pool_public_key, index})
  end

  @impl SharedSecretsKeystore
  @spec wrap_secrets(key :: binary()) ::
          {enc_transaction_seed :: binary(), enc_network_pool_seed :: binary()}
  def wrap_secrets(key) do
    GenStateMachine.call(__MODULE__, {:wrap_secrets, key})
  end

  @impl SharedSecretsKeystore
  @spec unwrap_secrets(encrypted_secrets :: binary(), encrypted_key :: binary(), DateTime.t()) ::
          :ok | :error
  def unwrap_secrets(
        secrets,
        encrypted_secret_key,
        date = %DateTime{}
      ) do
    GenStateMachine.call(__MODULE__, {:unwrap_secrets, secrets, encrypted_secret_key, date})
  end

  @impl SharedSecretsKeystore
  @spec get_network_pool_key_index() :: non_neg_integer()
  def get_network_pool_key_index do
    GenStateMachine.call(__MODULE__, :get_network_pool_key_index)
  end

  @impl SharedSecretsKeystore
  @spec set_network_pool_key_index(non_neg_integer()) :: :ok
  def set_network_pool_key_index(index) do
    GenStateMachine.cast(__MODULE__, {:set_network_pool_key_index, index})
  end

  @impl SharedSecretsKeystore
  @spec get_node_shared_key_index() :: non_neg_integer()
  def get_node_shared_key_index do
    GenStateMachine.call(__MODULE__, :get_node_shared_key_index)
  end

  @impl SharedSecretsKeystore
  @spec set_node_shared_secrets_key_index(non_neg_integer()) :: :ok
  def set_node_shared_secrets_key_index(index) do
    GenStateMachine.cast(__MODULE__, {:set_node_shared_secrets_key_index, index})
  end

  @impl GenStateMachine
  def init(_) do
    node_shared_secrets_chain =
      TransactionChain.list_transactions_by_type(
        :node_shared_secrets,
        [
          :address,
          data: [:keys],
          validation_stamp: [:timestamp]
        ]
      )

    nb_node_shared_secrets_keys = Enum.count(node_shared_secrets_chain)

    Logger.info("Node shared secrets keys positioned at #{nb_node_shared_secrets_keys}")

    nb_network_pool_keys = TransactionChain.count_transactions_by_type(:node_rewards)
    Logger.info("Network pool keys positioned at #{nb_network_pool_keys}")

    {:ok, :idle,
     %{
       shared_secrets_index: nb_node_shared_secrets_keys,
       network_pool_index: nb_network_pool_keys,
       daily_nonce_keys: %{}
     }, {:next_event, :internal, {:initial_load, node_shared_secrets_chain}}}
  end

  def handle_event(:internal, {:initial_load, node_shared_secrets_chain}, :idle, data) do
    case Enum.at(node_shared_secrets_chain, 0) do
      nil ->
        :keep_state_and_data

      %Transaction{
        address: address,
        data: %TransactionData{keys: keys = %Keys{secret: secret}},
        validation_stamp: %ValidationStamp{timestamp: timestamp}
      } ->
        if Keys.authorized_key?(keys, Crypto.last_node_public_key()) do
          encrypted_secret_key = Keys.get_encrypted_key(keys, Crypto.last_node_public_key())

          daily_nonce_date = SharedSecrets.next_application_date(timestamp)

          {:ok, new_data} =
            do_unwrap_secrets(secret, encrypted_secret_key, daily_nonce_date, data)

          Logger.info("Node shared secrets loaded",
            transaction_address: Base.encode16(address),
            transaction_type: :node_shared_secrets
          )

          {:next_state, :authorized, new_data}
        else
          :keep_state_and_data
        end
    end
  end

  @impl GenStateMachine
  def handle_event(
        {:call, from},
        {:sign_with_node_shared_key, data},
        :authorized,
        %{transaction_seed: seed, shared_secrets_index: index}
      ) do
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
        %{network_pool_seed: seed, network_pool_index: index}
      ) do
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
        data
      ) do
    case do_unwrap_secrets(encrypted_secrets, encrypted_aes_key, timestamp, data) do
      {:ok, new_data} ->
        {:next_state, :authorized, new_data, {:reply, from, :ok}}

      {:error, :decryption_failed} ->
        Logger.error("Cannot decrypt the node shared secrets")
        {:keep_state_and_data, {:reply, from, :error}}
    end
  end

  def handle_event(
        {:call, from},
        :get_node_shared_key_index,
        _,
        _data = %{shared_secrets_index: index}
      ) do
    {:keep_state_and_data, {:reply, from, index}}
  end

  def handle_event(
        {:call, from},
        :get_network_pool_key_index,
        _,
        _data = %{network_pool_index: index}
      ) do
    {:keep_state_and_data, {:reply, from, index}}
  end

  def handle_event(:cast, {:set_network_pool_key_index, index}, _, data) do
    {:keep_state, Map.put(data, :network_pool_index, index)}
  end

  def handle_event(:cast, {:set_node_shared_secrets_key_index, index}, _, data) do
    {:keep_state, Map.put(data, :shared_secrets_index, index)}
  end

  defp do_unwrap_secrets(
         encrypted_secrets,
         encrypted_aes_key,
         timestamp,
         data = %{daily_nonce_keys: daily_nonce_keys}
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

      new_data =
        data
        |> Map.put(:daily_nonce_keys, new_keys)
        |> Map.put(:transaction_seed, transaction_seed)
        |> Map.put(:network_pool_seed, network_pool_seed)

      {:ok, new_data}
    end
  end

  defp previous_keypair(seed, 0) do
    Crypto.derive_keypair(seed, 0)
  end

  defp previous_keypair(seed, index) do
    Crypto.derive_keypair(seed, index - 1)
  end
end
