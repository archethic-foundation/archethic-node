defmodule Archethic.SharedSecrets do
  @moduledoc false

  alias __MODULE__.MemTables.NetworkLookup
  alias __MODULE__.MemTables.OriginKeyLookup
  alias __MODULE__.MemTablesLoader
  alias __MODULE__.NodeRenewal
  alias __MODULE__.NodeRenewalScheduler

  alias Archethic.Crypto

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction

  alias Archethic.Utils

  alias Crontab.CronExpression.Parser, as: CronParser

  require Logger

  @type origin_family :: :software | :hardware | :biometric | :usb

  @spec list_origin_families() :: list(origin_family())
  def list_origin_families, do: [:software, :hardware, :biometric]

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
  Checks if the Origin public key already exists.
  """
  @spec has_origin_public_key?(origin_public_key :: Crypto.key()) :: boolean()
  defdelegate has_origin_public_key?(origin_public_key), to: OriginKeyLookup, as: :has_public_key?

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
          aes_key :: binary(),
          index :: non_neg_integer()
        ) :: Transaction.t()
  defdelegate new_node_shared_secrets_transaction(
                authorized_node_public_keys,
                daily_nonce_seed,
                aes_key,
                index
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
      id when id in [:software, :on_chain_wallet] ->
        :software

      id when id in [:tpm, :usb] ->
        :hardware

      _ ->
        :biometric
    end
  end

  @doc """
  Get the last shared secrets scheduling date from a given date
  """
  @spec get_last_scheduling_date(DateTime.t()) :: DateTime.t()
  def get_last_scheduling_date(date_from = %DateTime{}) do
    Application.get_env(:archethic, NodeRenewalScheduler)
    |> Keyword.fetch!(:interval)
    |> CronParser.parse!(true)
    |> Utils.previous_date(date_from)
  end

  @persistent_keys %{nss: :node_shared_secrets_gen_addr, origin: :origin_gen_addr}
  def genesis_address_keys(), do: @persistent_keys

  @spec persist_gen_addr(:node_shared_secrets) :: :ok | :error
  def persist_gen_addr(:node_shared_secrets) do
    try do
      case TransactionChain.list_addresses_by_type(:node_shared_secrets)
           |> Stream.take(1)
           |> Enum.at(0) do
        nil ->
          :error

        addr ->
          :persistent_term.put(@persistent_keys.nss, TransactionChain.get_genesis_address(addr))
          :ok
      end
    rescue
      error ->
        Logger.debug(error, nss: :error)
        :error
    end
  end

  @spec persist_gen_addr(:origin) :: :ok
  def persist_gen_addr(:origin) do
    try do
      software_gen_addr =
        get_origin_family_seed(:software)
        |> Crypto.derive_keypair(0)
        |> elem(0)
        |> Crypto.derive_address()

      usb_gen_addr =
        get_origin_family_seed(:usb)
        |> Crypto.derive_keypair(0)
        |> elem(0)
        |> Crypto.derive_address()

      biometric_gen_addr =
        get_origin_family_seed(:biometric)
        |> Crypto.derive_keypair(0)
        |> elem(0)
        |> Crypto.derive_address()

      :persistent_term.put(@persistent_keys.origin, [
        software_gen_addr,
        usb_gen_addr,
        biometric_gen_addr
      ])

      :ok
    rescue
      error ->
        Logger.debug(error, ss_o: :error)
        :error
    end
  end

  @spec genesis_address(:origin | :node_shared_secrets) :: list(binary()) | binary() | nil
  def genesis_address(:origin) do
    :persistent_term.get(@persistent_keys.origin, [])
  end

  def genesis_address(:node_shared_secrets) do
    :persistent_term.get(@persistent_keys.nss, nil)
  end

  @doc """
  Returns Origin id from Origin Public Key
  """
  @spec origin_family_from_public_key(<<_::16, _::_*8>>) :: origin_family()
  def origin_family_from_public_key(<<_curve_id::8, origin_id::8, _public_key::binary>>) do
    get_origin_family_from_origin_id(origin_id)
  end
end
