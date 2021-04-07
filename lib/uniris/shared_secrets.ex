defmodule Uniris.SharedSecrets do
  @moduledoc false

  alias Uniris.Crypto

  alias Uniris.Reward

  alias __MODULE__.MemTables.NetworkLookup
  alias __MODULE__.MemTables.OriginKeyLookup
  alias __MODULE__.MemTablesLoader
  alias __MODULE__.NodeRenewal
  alias __MODULE__.NodeRenewalScheduler

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Keys

  @type origin_family :: :software | :usb | :biometric

  @spec list_origin_families() :: list(origin_family())
  def list_origin_families, do: [:software, :usb, :biometric]

  @doc """
  List the origin public keys
  """
  @spec list_origin_public_keys() :: list(Crypto.key())
  defdelegate list_origin_public_keys, to: OriginKeyLookup, as: :list_public_keys

  @doc """
  List the origin public keys
  """
  @spec list_origin_public_keys(origin_family()) :: list(Crypto.key())
  defdelegate list_origin_public_keys(family), to: OriginKeyLookup, as: :list_public_keys

  @doc """
  Add an origin public key to the key lookup
  """
  @spec add_origin_public_key(origin_family(), Crypto.key()) :: :ok
  defdelegate add_origin_public_key(family, key), to: OriginKeyLookup, as: :add_public_key

  @doc """
  Get the last network pool address
  """
  @spec get_network_pool_address() :: Crypto.key()
  defdelegate get_network_pool_address, to: NetworkLookup

  @doc """
  Get the last daily nonce public key
  """
  @spec get_daily_nonce_public_key() :: Crypto.key()
  defdelegate get_daily_nonce_public_key, to: NetworkLookup

  @doc """
  Get the daily nonce public key before this date
  """
  @spec get_daily_nonce_public_key_at(DateTime.t()) :: Crypto.key()
  defdelegate get_daily_nonce_public_key_at(date), to: NetworkLookup

  @doc """
  Create a new transaction for node shared secrets renewal generating secret encrypted using the aes key and daily nonce seed
  for the authorized nodes public keys
  """
  @spec new_node_shared_secrets_transaction(
          authorized_node_public_keys :: list(Crypto.key()),
          daily_nonce_seed :: binary(),
          aes_key :: binary()
        ) :: Transaction.t()
  defdelegate new_node_shared_secrets_transaction(
                authorized_node_public_keys,
                daily_nonce_seed,
                aes_key
              ),
              to: NodeRenewal

  @doc """
  Load the transaction into the Shared Secrets context
  by filling memory tables and setup the new node shared secret renewal if applicable.

  It also start the scheduler if the node is elected as validation node and if the scheduler is not already started.
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(tx = %Transaction{}) do
    MemTablesLoader.load_transaction(tx)
    do_load_transaction(tx)
  end

  defp do_load_transaction(%Transaction{
         type: :node_shared_secrets,
         data: %TransactionData{keys: keys}
       }) do
    if Crypto.node_public_key() in Keys.list_authorized_keys(keys) do
      NodeRenewalScheduler.start_scheduling()
      Reward.start_network_pool_scheduling()
    end
  end

  defp do_load_transaction(_), do: :ok
end
