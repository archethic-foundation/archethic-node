defmodule Archethic.Crypto.SharedSecretsKeystore.SoftwareImpl do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.Crypto.SharedSecretsKeystore

  alias Archethic.DB

  alias Archethic.SharedSecrets

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership

  use GenServer
  @vsn 2

  require Logger

  @behaviour SharedSecretsKeystore

  @keystore_table :archethic_shared_secrets_keystore
  @daily_keys :archethic_shared_secrets_daily_keys

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl GenServer
  def init(_) do
    :ets.new(@keystore_table, [:set, :public, :named_table, read_concurrency: true])
    :ets.new(@daily_keys, [:ordered_set, :public, :named_table, read_concurrency: true])

    load_storage_nonce()

    nb_node_shared_secrets_keys =
      TransactionChain.count_transactions_by_type(:node_shared_secrets)

    Logger.info("Node shared secrets keys positioned at #{nb_node_shared_secrets_keys}")

    nb_reward_keys =
      TransactionChain.count_transactions_by_type(:node_rewards) +
        TransactionChain.count_transactions_by_type(:mint_rewards)

    Logger.info("Network pool keys positioned at #{nb_reward_keys}")

    :ets.insert(@keystore_table, {:shared_secrets_index, nb_node_shared_secrets_keys})
    :ets.insert(@keystore_table, {:reward_index, nb_reward_keys})

    :node_shared_secrets
    |> TransactionChain.list_addresses_by_type()
    |> Stream.take(-2)
    |> Enum.each(&load_node_shared_secrets_tx/1)

    {:ok, %{}}
  end

  @impl GenServer
  def code_change(1, state, _extra) do
    [reward_sign_fun] = :ets.take(@keystore_table, :network_pool_sign_fun)
    [reward_public_key_fun] = :ets.take(@keystore_table, :network_pool_public_key_fun)
    [reward_seed_wrap_fun] = :ets.take(@keystore_table, :network_pool_seed_wrap_fun)

    :ets.insert(@keystore_table, {:reward_sign_fun, reward_sign_fun})
    :ets.insert(@keystore_table, {:reward_public_key_fun, reward_public_key_fun})
    :ets.insert(@keystore_table, {:reward_seed_wrap_fun, reward_seed_wrap_fun})

    :node_shared_secrets
    |> TransactionChain.list_addresses_by_type()
    |> Stream.take(-2)
    |> Enum.each(&load_node_shared_secrets_tx/1)

    {:ok, state}
  end

  # we store functions in the ETS table, so we need to reload them
  # every upgrade to avoid: "xxx is invalid, likely because it points to an old version of the code"
  def code_change(_, state, _extra) do
    :node_shared_secrets
    |> TransactionChain.list_addresses_by_type()
    |> Stream.take(-2)
    |> Enum.each(&load_node_shared_secrets_tx/1)

    {:ok, state}
  end

  defp load_storage_nonce do
    case DB.get_bootstrap_info("storage_nonce") do
      nil ->
        nil

      storage_nonce ->
        :ets.insert(@keystore_table, {:storage_nonce, storage_nonce})
    end
  end

  defp load_node_shared_secrets_tx(nil), do: :ok

  defp load_node_shared_secrets_tx(address) do
    {:ok,
     %Transaction{
       data: %TransactionData{
         ownerships: [ownership = %Ownership{secret: secret}]
       },
       validation_stamp: %ValidationStamp{timestamp: timestamp}
     }} =
      TransactionChain.get_transaction(address, [
        :address,
        data: [:ownerships],
        validation_stamp: [:timestamp]
      ])

    node_public_key = Crypto.first_node_public_key()

    if Ownership.authorized_public_key?(ownership, node_public_key) do
      encrypted_secret_key = Ownership.get_encrypted_key(ownership, node_public_key)

      daily_nonce_date = SharedSecrets.next_application_date(timestamp)

      :ok = do_unwrap_secrets(secret, encrypted_secret_key, daily_nonce_date)

      Logger.info("Node shared secrets loaded",
        transaction_address: Base.encode16(address),
        transaction_type: :node_shared_secrets
      )
    end
  end

  @impl SharedSecretsKeystore
  def sign_with_node_shared_secrets_key(data) do
    [{_, index}] = :ets.lookup(@keystore_table, :shared_secrets_index)
    sign_with_node_shared_secrets_key(data, index)
  end

  @impl SharedSecretsKeystore
  def sign_with_node_shared_secrets_key(data, index) do
    [{_, sign_fun}] = :ets.lookup(@keystore_table, :transaction_sign_fun)
    sign_fun.(data, index)
  end

  @impl SharedSecretsKeystore
  def sign_with_reward_key(data) do
    [{_, index}] = :ets.lookup(@keystore_table, :reward_index)
    sign_with_reward_key(data, index)
  end

  @impl SharedSecretsKeystore
  def sign_with_reward_key(data, index) do
    [{_, sign_fun}] = :ets.lookup(@keystore_table, :reward_sign_fun)
    sign_fun.(data, index)
  end

  @impl SharedSecretsKeystore
  def sign_with_daily_nonce_key(data, timestamp) do
    timestamp = DateTime.to_unix(timestamp)

    sign_fun =
      case :ets.lookup(@daily_keys, timestamp) do
        [{_, sign_fun}] ->
          sign_fun

        [] ->
          timestamp = :ets.prev(@daily_keys, timestamp)
          [{_, sign_fun}] = :ets.lookup(@daily_keys, timestamp)
          sign_fun
      end

    sign_fun.(data)
  end

  @impl SharedSecretsKeystore
  def node_shared_secrets_public_key(index) do
    [{_, public_key_fun}] = :ets.lookup(@keystore_table, :transaction_public_key_fun)
    public_key_fun.(index)
  end

  @impl SharedSecretsKeystore
  def reward_public_key(index) do
    [{_, public_key_fun}] = :ets.lookup(@keystore_table, :reward_public_key_fun)
    public_key_fun.(index)
  end

  @impl SharedSecretsKeystore
  def wrap_secrets(secret_key) do
    [{_, transaction_seed_wrap_fun}] = :ets.lookup(@keystore_table, :transaction_seed_wrap_fun)
    [{_, reward_seed_wrap_fun}] = :ets.lookup(@keystore_table, :reward_seed_wrap_fun)

    encrypted_transaction_seed = transaction_seed_wrap_fun.(secret_key)
    encrypted_reward_seed = reward_seed_wrap_fun.(secret_key)

    {encrypted_transaction_seed, encrypted_reward_seed}
  end

  @impl SharedSecretsKeystore
  def unwrap_secrets(encrypted_secrets, encrypted_aes_key, timestamp) do
    case do_unwrap_secrets(encrypted_secrets, encrypted_aes_key, timestamp) do
      :ok ->
        :ok

      {:error, :decryption_failed} ->
        Logger.error("Cannot decrypt the node shared secrets")
        :error
    end
  end

  @impl SharedSecretsKeystore
  def get_node_shared_key_index do
    [{_, index}] = :ets.lookup(@keystore_table, :shared_secrets_index)
    index
  end

  @impl SharedSecretsKeystore
  def get_reward_key_index do
    [{_, index}] = :ets.lookup(@keystore_table, :reward_index)
    index
  end

  @impl SharedSecretsKeystore
  def set_reward_key_index(index) do
    true = :ets.insert(@keystore_table, {:reward_index, index})
    :ok
  end

  @impl SharedSecretsKeystore
  def set_node_shared_secrets_key_index(index) do
    true = :ets.insert(@keystore_table, {:shared_secrets_index, index})
    :ok
  end

  defp do_unwrap_secrets(
         encrypted_secrets,
         encrypted_aes_key,
         timestamp
       ) do
    <<enc_daily_nonce_seed::binary-size(60), enc_transaction_seed::binary-size(60),
      enc_reward_seed::binary-size(60)>> = encrypted_secrets

    with {:ok, aes_key} <- Crypto.ec_decrypt_with_first_node_key(encrypted_aes_key),
         {:ok, daily_nonce_seed} <- Crypto.aes_decrypt(enc_daily_nonce_seed, aes_key),
         {:ok, transaction_seed} <- Crypto.aes_decrypt(enc_transaction_seed, aes_key),
         {:ok, reward_seed} <- Crypto.aes_decrypt(enc_reward_seed, aes_key) do
      sign_daily_nonce_fun = fn data ->
        {pub, pv} = Crypto.generate_deterministic_keypair(daily_nonce_seed)
        Logger.debug("Sign with the daily nonce for the public key #{Base.encode16(pub)}")

        Crypto.sign(data, pv)
      end

      transaction_sign_fun = fn data, index ->
        {_, pv} = Crypto.derive_keypair(transaction_seed, index)
        Crypto.sign(data, pv)
      end

      reward_sign_fun = fn data, index ->
        {_, pv} = Crypto.derive_keypair(reward_seed, index)
        Crypto.sign(data, pv)
      end

      transaction_public_key_fun = fn index ->
        {pub, _} = Crypto.derive_keypair(transaction_seed, index)
        pub
      end

      reward_public_key_fun = fn index ->
        {pub, _} = Crypto.derive_keypair(reward_seed, index)
        pub
      end

      transaction_seed_wrap_fun = fn secret_key ->
        Crypto.aes_encrypt(transaction_seed, secret_key)
      end

      reward_seed_wrap_fun = fn secret_key ->
        Crypto.aes_encrypt(reward_seed, secret_key)
      end

      :ets.insert(@daily_keys, {DateTime.to_unix(timestamp), sign_daily_nonce_fun})
      remove_older_daily_keys(DateTime.to_unix(timestamp))

      :ets.insert(@keystore_table, {:transaction_sign_fun, transaction_sign_fun})
      :ets.insert(@keystore_table, {:reward_sign_fun, reward_sign_fun})
      :ets.insert(@keystore_table, {:transaction_public_key_fun, transaction_public_key_fun})
      :ets.insert(@keystore_table, {:reward_public_key_fun, reward_public_key_fun})
      :ets.insert(@keystore_table, {:transaction_seed_wrap_fun, transaction_seed_wrap_fun})
      :ets.insert(@keystore_table, {:reward_seed_wrap_fun, reward_seed_wrap_fun})

      :ok
    end
  end

  defp remove_older_daily_keys(unix_timestamp) do
    case :ets.prev(@daily_keys, unix_timestamp) do
      :"$end_of_table" ->
        :ok

      prev_unix_timestamp ->
        # generate match pattern
        # :ets.fun2ms(fn {key, _sign_function} -> key < prev_unix_timestamp end)

        match_pattern = [
          {{:"$1", :_}, [{:<, :"$1", prev_unix_timestamp}], [true]}
        ]

        :ets.select_delete(@daily_keys, match_pattern)
    end
  end

  @doc """
  Load the storage nonce
  """
  @impl SharedSecretsKeystore
  @spec set_storage_nonce(binary()) :: :ok
  def set_storage_nonce(storage_nonce) when is_binary(storage_nonce) do
    DB.set_bootstrap_info("storage_nonce", storage_nonce)
    true = :ets.insert(@keystore_table, {:storage_nonce, storage_nonce})
    :ok
  end

  @doc """
  Get the storage nonce
  """
  @impl SharedSecretsKeystore
  @spec get_storage_nonce() :: binary()
  def get_storage_nonce do
    [{_, nonce}] = :ets.lookup(@keystore_table, :storage_nonce)
    nonce
  end
end
