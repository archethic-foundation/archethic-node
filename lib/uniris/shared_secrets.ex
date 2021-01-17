defmodule Uniris.SharedSecrets do
  @moduledoc false

  alias Uniris.Crypto

  alias __MODULE__.MemTables.OriginKeyLookup
  alias __MODULE__.MemTablesLoader
  alias __MODULE__.NodeRenewal

  alias Uniris.TransactionChain.Transaction

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
  by filling memory tables and setup the new node shared secret renewal if applicable
  """
  @spec load_transaction(Transaction.t()) :: :ok
  defdelegate load_transaction(tx), to: MemTablesLoader
end
