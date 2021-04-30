defmodule Uniris.Crypto.KeystoreLoader do
  @moduledoc false

  alias Uniris.Crypto
  alias Uniris.Crypto.KeystoreCounter

  alias Uniris.SharedSecrets

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Keys

  use GenServer

  require Logger

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    nb_node_keys =
      Crypto.node_public_key(0)
      |> Crypto.hash()
      |> TransactionChain.get_last_address()
      |> TransactionChain.size()

    if nb_node_keys > 0 do
      KeystoreCounter.set_node_key_counter(nb_node_keys)
      Logger.debug("#{nb_node_keys} node keys loaded into the keystore")
    end

    nb_node_shared_secrets_keys =
      TransactionChain.count_transactions_by_type(:node_shared_secrets)

    if nb_node_shared_secrets_keys > 0 do
      KeystoreCounter.set_node_shared_secrets_key_counter(nb_node_shared_secrets_keys)
      Logger.debug("#{nb_node_shared_secrets_keys} node shared keys loaded into the keystore")
    end

    nb_network_pool_keys = TransactionChain.count_transactions_by_type(:node_rewards)

    if nb_network_pool_keys > 0 do
      KeystoreCounter.set_network_pool_key_counter(nb_network_pool_keys)
      Logger.debug("#{nb_network_pool_keys} network pool keys loaded into the keystore")
    end

    last_node_shared_tx =
      TransactionChain.list_transactions_by_type(:node_shared_secrets, [
        :address,
        :type,
        :timestamp,
        data: [:keys]
      ])
      |> Enum.at(0)

    case last_node_shared_tx do
      nil ->
        {:ok, []}

      tx ->
        load_transaction(tx)
        {:ok, []}
    end
  end

  @doc """
  Load the transaction for the Keystore indexing
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(%Transaction{
        type: :node,
        address: address,
        previous_public_key: previous_public_key
      }) do
    node_first_public_key = Crypto.node_public_key(0)

    case TransactionChain.get_first_public_key(previous_public_key) do
      ^node_first_public_key ->
        nb_transactions = TransactionChain.size(address)
        KeystoreCounter.set_node_key_counter(nb_transactions)

      _ ->
        :ok
    end
  end

  def load_transaction(%Transaction{
        address: address,
        type: :node_shared_secrets,
        timestamp: timestamp,
        data: %TransactionData{keys: keys = %Keys{secret: secret}}
      }) do
    nb_transactions = TransactionChain.size(address)
    KeystoreCounter.set_node_shared_secrets_key_counter(nb_transactions)

    if Keys.authorized_key?(keys, Crypto.node_public_key()) do
      encrypted_secret_key = Keys.get_encrypted_key(keys, Crypto.node_public_key())

      <<daily_nonce_seed::binary-size(60), transaction_seed::binary-size(60),
        network_seed::binary-size(60)>> = secret

      :ok =
        Crypto.decrypt_and_set_node_shared_secrets_transaction_seed(
          transaction_seed,
          encrypted_secret_key
        )

      :ok =
        Crypto.decrypt_and_set_node_shared_secrets_network_pool_seed(
          network_seed,
          encrypted_secret_key
        )

      daily_nonce_date = SharedSecrets.next_application_date(timestamp)

      :ok =
        Crypto.decrypt_and_set_daily_nonce_seed(
          daily_nonce_seed,
          encrypted_secret_key,
          daily_nonce_date
        )
    else
      :ok
    end
  end

  def load_transaction(%Transaction{type: :node_rewards, address: address}) do
    nb_transactions = TransactionChain.size(address)
    KeystoreCounter.set_network_pool_key_counter(nb_transactions)
  end

  def load_transaction(_), do: :ok
end
