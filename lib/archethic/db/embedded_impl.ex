defmodule Archethic.DB.EmbeddedImpl do
  @moduledoc """
  Custom database implementation for Archethic storage layer using File for transaction chain storages and index backup
  while using a key value in memory for fast lookup
  """

  alias Archethic.BeaconChain.Summary
  alias Archethic.BeaconChain.SummaryAggregate

  alias Archethic.Crypto

  alias Archethic.DB

  alias __MODULE__.BootstrapInfo
  alias __MODULE__.ChainIndex
  alias __MODULE__.ChainReader
  alias __MODULE__.ChainWriter
  alias __MODULE__.P2PView
  alias __MODULE__.StatsInfo

  alias Archethic.TransactionChain.Transaction

  alias Archethic.Utils

  defdelegate child_spec(opts), to: __MODULE__.Supervisor

  @behaviour Archethic.DB

  @doc """
  Return the path of the database folder
  """
  @spec filepath() :: String.t()
  def filepath do
    try do
      :persistent_term.get(:archethic_db_path)
    rescue
      ArgumentError ->
        path = Utils.mut_dir()
        :persistent_term.put(:archethic_db_path, path)
        path
    end
  end

  @doc """
  Write a single transaction and append it to its chain
  """
  @spec write_transaction(Transaction.t(), DB.storage_type()) :: :ok
  def write_transaction(tx, storage_type \\ :chain)

  def write_transaction(tx = %Transaction{}, :chain) do
    if ChainIndex.transaction_exists?(tx.address, filepath()) do
      {:error, :transaction_already_exists}
    else
      previous_address = Transaction.previous_address(tx)

      genesis_address =
        case ChainIndex.get_tx_entry(previous_address, filepath()) do
          {:ok, %{genesis_address: genesis_address}} ->
            genesis_address

          {:error, :not_exists} ->
            previous_address
        end

      ChainWriter.append_transaction(genesis_address, tx)

      # Delete IO transaction if it exists as it is now stored as a chain
      delete_io_transaction(tx.address)
    end
  end

  def write_transaction(tx = %Transaction{}, :io) do
    if ChainIndex.transaction_exists?(tx.address, :io, filepath()) do
      {:error, :transaction_already_exists}
    else
      ChainWriter.write_io_transaction(tx, filepath())
    end
  end

  defp delete_io_transaction(address) do
    ChainWriter.io_path(filepath(), address) |> File.rm()
    :ok
  end

  @doc """
  Write a beacon summary in DB
  """
  @spec write_beacon_summary(Summary.t()) :: :ok
  def write_beacon_summary(summary = %Summary{}) do
    ChainWriter.write_beacon_summary(summary, filepath())
  end

  @doc """
  Remove the beacon summaries files
  """
  @spec clear_beacon_summaries() :: :ok
  def clear_beacon_summaries do
    filepath()
    |> ChainWriter.base_beacon_path()
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.each(&File.rm!/1)
  end

  @doc """
  Write a beacon summaries aggregate
  """
  @spec write_beacon_summaries_aggregate(SummaryAggregate.t()) :: :ok
  def write_beacon_summaries_aggregate(aggregate = %SummaryAggregate{}) do
    ChainWriter.write_beacon_summaries_aggregate(aggregate, filepath())
  end

  @doc """
  Determine if the transaction exists or not
  """
  @spec transaction_exists?(address :: binary(), storage_type :: DB.storage_type()) :: boolean()
  def transaction_exists?(address, storage_type) when is_binary(address) do
    ChainIndex.transaction_exists?(address, storage_type, filepath())
  end

  @doc """
  Get a transaction at the given address
  Read from storage first and maybe read from IO storage if flag is passed
  """
  @spec get_transaction(address :: binary(), fields :: list(), storage_type :: DB.storage_type()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_transaction(address, fields \\ [], storage_type \\ :chain)
      when is_binary(address) and is_list(fields) do
    case ChainReader.get_transaction(address, fields, filepath()) do
      {:ok, transaction} ->
        {:ok, transaction}

      {:error, :transaction_not_exists} ->
        if storage_type == :io do
          ChainReader.get_io_transaction(address, fields, filepath())
        else
          {:error, :transaction_not_exists}
        end
    end
  end

  @doc """
  Get a beacon summary at the given address
  """
  @spec get_beacon_summary(summary_address :: binary()) ::
          {:ok, Summary.t()} | {:error, :summary_not_exists}
  def get_beacon_summary(summary_address) when is_binary(summary_address) do
    ChainReader.get_beacon_summary(summary_address, filepath())
  end

  @doc """
  Get a beacon summaries aggregate at a given date
  """
  @spec get_beacon_summaries_aggregate(DateTime.t()) ::
          {:ok, SummaryAggregate.t()} | {:error, :not_exists}
  def get_beacon_summaries_aggregate(date = %DateTime{}) do
    ChainReader.get_beacon_summaries_aggregate(date, filepath())
  end

  @doc """
  Get a transaction chain

  The returned values will be splitted according to the pagination state presents in the options
  """
  @spec get_transaction_chain(address :: binary(), fields :: list(), opts :: list()) ::
          {transactions_by_page :: list(Transaction.t()), more? :: boolean(),
           paging_address :: nil | binary()}
  def get_transaction_chain(address, fields \\ [], opts \\ [])
      when is_binary(address) and is_list(fields) and is_list(opts) do
    ChainReader.get_transaction_chain(address, fields, opts, filepath())
  end

  @doc """
  Return the size of a transaction chain
  """
  @spec chain_size(address :: binary()) :: non_neg_integer()
  def chain_size(address) when is_binary(address) do
    ChainIndex.chain_size(address, filepath())
  end

  @doc """
  List all the transaction by the given type
  """
  @spec list_transactions_by_type(Transaction.transaction_type(), fields :: list()) ::
          Enumerable.t() | list(Transaction.t())
  def list_transactions_by_type(type, fields \\ []) when is_atom(type) and is_list(fields) do
    type
    |> ChainIndex.get_addresses_by_type(filepath())
    |> Stream.map(fn address ->
      {:ok, tx} = get_transaction(address, fields)
      tx
    end)
  end

  @doc """
  Stream all the addresses for a transaction type
  """
  @spec list_addresses_by_type(Transaction.transaction_type()) :: Enumerable.t() | list(binary())
  def list_addresses_by_type(type) when is_atom(type) do
    ChainIndex.get_addresses_by_type(type, filepath())
  end

  @doc """
  Stream all the addresses from the Genesis address(following it).
  """
  @spec list_chain_addresses(binary()) ::
          Enumerable.t() | list({binary(), DateTime.t()})
  def list_chain_addresses(address) when is_binary(address) do
    ChainIndex.list_chain_addresses(address, filepath())
  end

  @doc """
  Stream all the public keys until a date, from a public key.
  """
  @spec list_chain_public_keys(binary(), DateTime.t()) ::
          Enumerable.t() | list({binary(), DateTime.t()})
  def list_chain_public_keys(public_key, until) when is_binary(public_key) do
    ChainIndex.list_chain_public_keys(public_key, until, filepath())
  end

  @doc """
  Stream all genesis addresses
  """
  @spec list_genesis_addresses() :: Enumerable.t()
  def list_genesis_addresses(), do: ChainIndex.list_genesis_addresses(filepath())

  @doc """
  Count the number of transactions for a given type
  """
  @spec count_transactions_by_type(Transaction.transaction_type()) :: non_neg_integer()
  def count_transactions_by_type(type) when is_atom(type) do
    ChainIndex.count_transactions_by_type(type)
  end

  @doc """
  Return the last address stored for a chain
  """
  @spec get_last_chain_address_stored(genesis_address :: Crypto.prepended_hash()) ::
          Crypto.prepended_hash() | nil
  def get_last_chain_address_stored(genesis_address) when is_binary(genesis_address) do
    ChainIndex.get_last_chain_address_stored(genesis_address, filepath())
  end

  @doc """
  Return the last address from the given transaction's address until the given date along with its timestamp
  """
  @spec get_last_chain_address(address :: binary(), until :: DateTime.t()) ::
          {address :: binary(), last_address_timestamp :: DateTime.t()}
  def get_last_chain_address(address, date = %DateTime{} \\ DateTime.utc_now())
      when is_binary(address) do
    ChainIndex.get_last_chain_address(address, date, filepath())
  end

  @doc """
  Reference a last address from a genesis address
  """
  @spec add_last_transaction_address(
          genesis_address :: binary(),
          address :: binary(),
          tx_time :: DateTime.t()
        ) :: :ok
  def add_last_transaction_address(genesis_address, address, date = %DateTime{})
      when is_binary(genesis_address) and is_binary(address) do
    ChainIndex.set_last_chain_address(genesis_address, address, date, filepath())
  end

  @doc """
  Return the genesis address of given chain's address

  If no genesis address is found, the given address is returned by default
  """
  @spec get_genesis_address(address :: Crypto.prepended_hash()) ::
          genesis_address :: Crypto.prepended_hash()
  def get_genesis_address(address) when is_binary(address) do
    ChainIndex.get_genesis_address(address, filepath())
  end

  @doc """
  Return the genesis address of given chain's address
  """
  @spec find_genesis_address(address :: Crypto.prepended_hash()) ::
          {:ok, genesis_address :: Crypto.prepended_hash()} | {:error, :not_found}
  def find_genesis_address(address) when is_binary(address) do
    ChainIndex.find_genesis_address(address, filepath())
  end

  @doc """
  Return the first public key of given chain's public key
  """
  @spec get_first_public_key(public_key :: Crypto.key()) :: Crypto.key()
  def get_first_public_key(public_key) when is_binary(public_key) do
    ChainIndex.get_first_public_key(public_key, filepath())
  end

  @doc """
  List all the transactions in chain storage
  """
  @spec list_transactions(fields :: list()) :: Enumerable.t() | list(Transaction.t())
  def list_transactions(fields \\ []) when is_list(fields) do
    filepath()
    |> ChainIndex.list_genesis_addresses()
    |> Stream.flat_map(&ChainReader.stream_chain(&1, fields, filepath()))
  end

  @doc """
  Stream chain tx from the beginning
  """
  @spec stream_chain(binary(), list()) :: Enumerable.t() | list(Transaction.t())
  def stream_chain(address, fields) do
    genesis = ChainIndex.get_genesis_address(address, filepath())
    ChainReader.stream_chain(genesis, fields, filepath())
  end

  @doc """
  List all the transactions in io storage
  """
  @spec list_io_transactions(fields :: list()) :: Enumerable.t() | list(Transaction.t())
  def list_io_transactions(fields \\ []) do
    ChainReader.list_io_transactions(fields, filepath())
  end

  @doc """
  List all the last transaction chain addresses
  """
  @spec list_last_transaction_addresses() :: Enumerable.t() | list(binary())
  def list_last_transaction_addresses do
    filepath()
    |> ChainIndex.list_genesis_addresses()
    |> Stream.map(&get_last_chain_address/1)
    |> Stream.map(fn {address, _time} -> address end)
  end

  @doc """
  Register the new stats from a self-repair cycle
  """
  @spec register_stats(
          time :: DateTime.t(),
          tps :: float(),
          nb_transactions :: non_neg_integer(),
          burned_fees :: non_neg_integer()
        ) ::
          :ok
  defdelegate register_stats(date, tps, nb_transactions, burned_fees),
    to: StatsInfo,
    as: :new_stats

  @doc """
  Return tps from the last self-repair cycle
  """
  @spec get_latest_tps() :: float()
  defdelegate get_latest_tps, to: StatsInfo, as: :get_tps

  @doc """
  Return burned_fees from the last self-repair cycle
  """
  @spec get_latest_burned_fees() :: non_neg_integer()
  defdelegate get_latest_burned_fees, to: StatsInfo, as: :get_burned_fees

  @doc """
  Return the last number of transaction in the network (from the previous self-repair cycles)
  """
  defdelegate get_nb_transactions, to: StatsInfo

  @spec set_bootstrap_info(String.t(), String.t()) :: :ok
  defdelegate set_bootstrap_info(key, value), to: BootstrapInfo, as: :set

  @spec get_bootstrap_info(key :: binary()) :: String.t() | nil
  defdelegate get_bootstrap_info(key), to: BootstrapInfo, as: :get

  @doc """
  Return the last node views from the last self-repair cycle
  """
  @spec register_p2p_summary(list()) :: :ok
  defdelegate register_p2p_summary(nodes_view), to: P2PView, as: :set_node_view

  @doc """
  Register a new node view from the last self-repair cycle
  """
  @spec get_last_p2p_summaries() ::
          list(
            {node_public_key :: Crypto.key(), available? :: boolean(),
             average_availability :: float(), availability_update :: DateTime.t(),
             network_patch :: String.t() | nil}
          )
  defdelegate get_last_p2p_summaries, to: P2PView, as: :get_views

  @doc """
  Stream first transactions address of a chain from genesis_address.
  """
  @spec list_first_addresses() :: Enumerable.t() | list(Crypto.prepended_hash())
  def list_first_addresses() do
    filepath()
    |> ChainIndex.list_genesis_addresses()
    |> Stream.map(fn gen_address ->
      gen_address
      |> list_chain_addresses()
      |> Enum.at(0)
      |> elem(0)
    end)
  end
end
