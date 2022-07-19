defmodule Archethic.DB.EmbeddedImpl do
  @moduledoc """
  Custom database implementation for Archethic storage layer using File for transaction chain storages and index backup
  while using a key value in memory for fast lookup
  """

  alias Archethic.Crypto

  alias __MODULE__.BootstrapInfo
  alias __MODULE__.ChainIndex
  alias __MODULE__.ChainReader
  alias __MODULE__.ChainWriter
  alias __MODULE__.P2PView
  alias __MODULE__.StatsInfo
  alias __MODULE__.Queue

  alias Archethic.TransactionChain.Transaction

  alias Archethic.Utils

  defdelegate child_spec(opts), to: __MODULE__.Supervisor

  @behaviour Archethic.DB

  @doc """
  Return the path of the database folder
  """
  @spec db_path() :: String.t()
  def db_path do
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
  Write the transaction chain through the a chain writer which will
  happens the transactions to the chain's file

  If a transaction already exists it will be discarded

  Indexes will then be filled with the relative transactions
  """
  @spec write_transaction_chain(list(Transaction.t())) :: :ok
  def write_transaction_chain(chain) do
    sorted_chain = Enum.sort_by(chain, & &1.validation_stamp.timestamp, {:asc, DateTime})

    previous_address =
      List.first(sorted_chain)
      |> Transaction.previous_address()

    genesis_address =
      case ChainIndex.get_tx_entry(previous_address, db_path()) do
        {:ok, %{genesis_address: genesis_address}} ->
          genesis_address

        _ ->
          previous_address
      end

    Queue.push(genesis_address, fn -> do_write_transaction_chain(genesis_address, chain) end)
  end

  defp do_write_transaction_chain(genesis_address, sorted_chain) do
    Enum.each(sorted_chain, fn tx ->
      unless ChainIndex.transaction_exists?(tx.address, db_path()) do
        ChainWriter.append_transaction(genesis_address, tx)
      end
    end)
  end

  @doc """
  Write a single transaction and append it to its chain
  """
  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(tx = %Transaction{}) do
    if ChainIndex.transaction_exists?(tx.address, db_path()) do
      {:error, :transaction_already_exists}
    else
      previous_address = Transaction.previous_address(tx)

      case ChainIndex.get_tx_entry(previous_address, db_path()) do
        {:ok, %{genesis_address: genesis_address}} ->
          Queue.push(genesis_address, fn -> do_write_transaction(genesis_address, tx) end)

        {:error, :not_exists} ->
          ChainWriter.append_transaction(previous_address, tx)
      end
    end
  end

  defp do_write_transaction(genesis_address, tx) do
    if ChainIndex.transaction_exists?(tx.address, db_path()) do
      {:error, :transaction_already_exists}
    else
      ChainWriter.append_transaction(genesis_address, tx)
    end
  end

  @doc """
  Write a transaction if a specific genesis address
  """
  @spec write_transaction_at(Transaction.t(), binary()) :: :ok
  def write_transaction_at(tx = %Transaction{}, genesis_address)
      when is_binary(genesis_address) do
    if ChainIndex.transaction_exists?(tx.address, db_path()) do
      {:error, :transaction_already_exists}
    else
      Queue.push(genesis_address, fn -> do_write_transaction_at(genesis_address, tx) end)
    end
  end

  defp do_write_transaction_at(genesis_address, tx) do
    if ChainIndex.transaction_exists?(tx.address, db_path()) do
      {:error, :transaction_already_exists}
    else
      ChainWriter.append_transaction(genesis_address, tx)
    end
  end

  @doc """
  Determine if the transaction exists or not
  """
  @spec transaction_exists?(address :: binary()) :: boolean()
  def transaction_exists?(address) when is_binary(address) do
    ChainIndex.transaction_exists?(address, db_path())
  end

  @doc """
  Get a transaction at the given address
  """
  @spec get_transaction(address :: binary(), fields :: list()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_transaction(address, fields \\ []) when is_binary(address) and is_list(fields) do
    ChainReader.get_transaction(address, fields, db_path())
  end

  @doc """
  Get a transaction chain

  The returned values will be splitted according to the pagination state presents in the options
  """
  @spec get_transaction_chain(address :: binary(), fields :: list(), opts :: list()) ::
          {transactions_by_page :: list(Transaction.t()), more? :: boolean(),
           paging_state :: nil | binary()}
  def get_transaction_chain(address, fields \\ [], opts \\ [])
      when is_binary(address) and is_list(fields) and is_list(opts) do
    ChainReader.get_transaction_chain(address, fields, opts, db_path())
  end

  @doc """
  Return the size of a transaction chain
  """
  @spec chain_size(address :: binary()) :: non_neg_integer()
  def chain_size(address) when is_binary(address) do
    ChainIndex.chain_size(address, db_path())
  end

  @doc """
  List all the transaction by the given type
  """
  @spec list_transactions_by_type(Transaction.transaction_type(), fields :: list()) ::
          Enumerable.t() | list(Transaction.t())
  def list_transactions_by_type(type, fields \\ []) when is_atom(type) and is_list(fields) do
    type
    |> ChainIndex.get_addresses_by_type(db_path())
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
    ChainIndex.get_addresses_by_type(type, db_path())
  end

  @doc """
  Count the number of transactions for a given type
  """
  @spec count_transactions_by_type(Transaction.transaction_type()) :: non_neg_integer()
  def count_transactions_by_type(type) when is_atom(type) do
    ChainIndex.count_transactions_by_type(type)
  end

  @doc """
  Return the last address from the given transaction's address until the given date
  """
  @spec get_last_chain_address(address :: binary(), until :: DateTime.t()) :: binary()
  def get_last_chain_address(address, date = %DateTime{} \\ DateTime.utc_now())
      when is_binary(address) do
    ChainIndex.get_last_chain_address(address, date, db_path())
  end

  @doc """
  Reference a last address from a previous address
  """
  @spec add_last_transaction_address(
          previous_address :: binary(),
          address :: binary(),
          tx_time :: DateTime.t()
        ) :: :ok
  def add_last_transaction_address(previous_address, address, date = %DateTime{})
      when is_binary(previous_address) and is_binary(address) do
    ChainIndex.set_last_chain_address(previous_address, address, date, db_path())
  end

  @doc """
  Return the first address of given chain's address
  """
  @spec get_first_chain_address(address :: binary()) :: binary()
  def get_first_chain_address(address) when is_binary(address) do
    ChainIndex.get_first_chain_address(address, db_path())
  end

  @doc """
  Return the first public key of given chain's public key
  """
  @spec get_first_public_key(public_key :: Crypto.key()) :: Crypto.key()
  def get_first_public_key(public_key) when is_binary(public_key) do
    ChainIndex.get_first_public_key(public_key, db_path())
  end

  @doc """
  List all the transactions
  """
  @spec list_transactions(fields :: list()) :: Enumerable.t() | list(Transaction.t())
  def list_transactions(fields \\ []) when is_list(fields) do
    db_path()
    |> ChainIndex.list_all_addresses()
    |> Stream.map(fn address ->
      {:ok, tx} = get_transaction(address, fields)
      tx
    end)
  end

  @doc """
  List all the last transaction chain addresses
  """
  @spec list_last_transaction_addresses() :: Enumerable.t() | list(binary())
  def list_last_transaction_addresses do
    ChainIndex.list_genesis_addresses()
    |> Stream.map(&get_last_chain_address/1)
  end

  @doc """
  Register the new stats from a self-repair cycle
  """
  @spec register_tps(time :: DateTime.t(), tps :: float(), nb_transactions :: non_neg_integer()) ::
          :ok
  defdelegate register_tps(date, tps, nb_transactions), to: StatsInfo, as: :new_stats

  @doc """
  Return tps from the last self-repair cycle
  """
  @spec get_latest_tps() :: float()
  defdelegate get_latest_tps, to: StatsInfo, as: :get_tps

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
  @spec register_p2p_summary(
          Crypto.key(),
          DateTime.t(),
          available? :: boolean(),
          avg_availability :: float()
        ) :: :ok
  defdelegate register_p2p_summary(node_public_key, date, available?, avg_availability),
    to: P2PView,
    as: :add_node_view

  @doc """
  Register a new node view from the last self-repair cycle
  """
  @spec get_last_p2p_summaries() :: %{
          (node_public_key :: Crypto.key()) => {
            available? :: boolean(),
            average_availability :: float()
          }
        }
  defdelegate get_last_p2p_summaries, to: P2PView, as: :get_views
end
