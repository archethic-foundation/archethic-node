defmodule Archethic.SharedSecrets do
  @moduledoc false

  alias Archethic.Crypto

  alias __MODULE__.MemTables.NetworkLookup
  alias __MODULE__.MemTables.OriginKeyLookup
  alias __MODULE__.MemTablesLoader
  alias __MODULE__.NodeRenewal
  alias __MODULE__.NodeRenewalScheduler

  alias Archethic.TransactionChain.Transaction

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
  Get the daily nonce public key before this date
  """
  @spec get_daily_nonce_public_key(DateTime.t()) :: Crypto.key()
  defdelegate get_daily_nonce_public_key(date \\ DateTime.utc_now()), to: NetworkLookup

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
  end

  @doc """
  Get the genesis daily nonce public key
  """
  @spec genesis_daily_nonce_public_key() :: Crypto.key()
  def genesis_daily_nonce_public_key,
    do: NetworkLookup.get_daily_nonce_public_key(~U[1970-01-01 00:00:00Z])

  @doc """
  Get the next application date
  """
  @spec next_application_date(DateTime.t()) :: DateTime.t()
  defdelegate next_application_date(date_from \\ DateTime.utc_now()), to: NodeRenewalScheduler

  def config_change(changed_conf) do
    changed_conf
    |> Keyword.get(NodeRenewalScheduler)
    |> NodeRenewalScheduler.config_change()
  end

  @doc """
  Get the origin seed for a given origin family
  """
  @spec get_origin_family_seed(origin_family()) :: binary()
  def get_origin_family_seed(origin_family) do
    <<Crypto.storage_nonce()::binary, Atom.to_string(origin_family)::binary>>
  end

  @doc """
  Get the origin family for a given origin id
  """
  @spec get_origin_family_from_origin_id(non_neg_integer()) :: origin_family()
  def get_origin_family_from_origin_id(origin_id) do
    case Crypto.key_origin(origin_id) do
      :software ->
        :software

      :on_chain_wallet ->
        :software

      _ ->
        :biometric
    end
  end
end
