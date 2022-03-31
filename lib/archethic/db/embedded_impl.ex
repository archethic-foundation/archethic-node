defmodule ArchEthic.DB.EmbeddedImpl do
  alias ArchEthic.Crypto

  alias __MODULE__.BootstrapInfo
  alias __MODULE__.Index
  alias __MODULE__.ChainReader
  alias __MODULE__.ChainWriter
  alias __MODULE__.P2PView
  alias __MODULE__.StatsInfo

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.Utils

  defdelegate child_spec(opts), to: __MODULE__.Supervisor

  # @behaviour ArchEthic.DB

  @spec write_transaction_chain(list(Transaction.t())) :: :ok
  def write_transaction_chain(chain) do
    sorted_chain = Enum.sort_by(chain, & &1.validation_stamp.timestamp, {:asc, DateTime})

    first_tx = List.first(sorted_chain)
    genesis_address = Transaction.previous_address(first_tx)

    Enum.each(sorted_chain, fn tx ->
      ChainWriter.append_transaction(genesis_address, tx)
    end)
  end

  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(tx) do
    previous_address = Transaction.previous_address(tx)

    case Index.get_tx_entry(previous_address) do
      {:ok, %{genesis_address: genesis_address}} ->
        ChainWriter.append_transaction(genesis_address, tx)

      {:error, :not_exists} ->
        ChainWriter.append_transaction(previous_address, tx)
    end
  end

  @spec transaction_exists?(binary()) :: boolean()
  def transaction_exists?(address) do
    Index.transaction_exists?(address)
  end

  defdelegate get_transaction(address, fields \\ []), to: ChainReader
  defdelegate get_transaction_chain(address, fields \\ [], opts \\ []), to: ChainReader

  @doc """
  Return the size of a transaction chain
  """
  @spec chain_size(binary()) :: non_neg_integer()
  def chain_size(address) do
    length(Index.get_chain_addresses(address))
  end

  @doc """
  List all the transaction by the given type
  """
  @spec list_transactions_by_type(Transaction.transaction_type(), list()) ::
          Enumerable.t() | list(Transaction.t())
  def list_transactions_by_type(type, fields \\ []) do
    type
    |> Index.get_addresses_by_type()
    |> Stream.map(fn address ->
      {:ok, tx} = get_transaction(address, fields)
      tx
    end)
  end

  @doc """
  Count the number of transactions for a given type
  """
  @spec count_transactions_by_type(Transaction.transaction_type()) :: non_neg_integer()
  def count_transactions_by_type(type) do
    type
    |> Index.get_addresses_by_type()
    |> length()
  end

  @doc """
  Return the last address from the given transaction's address until the given date
  """
  @spec get_last_chain_address(binary(), DateTime.t()) :: binary()
  def get_last_chain_address(address, date = %DateTime{} \\ DateTime.utc_now()) do
    Index.get_last_chain_address(address, date)
  end

  @doc """
  Reference a last address from a previous address
  """
  @spec add_last_transaction_address(binary(), binary(), DateTime.t()) :: :ok
  def add_last_transaction_address(previous_address, address, date = %DateTime{}) do
    Index.set_last_chain_address(previous_address, address, date)
  end

  @doc """
  Return the first address of given chain's address
  """
  @spec get_first_chain_address(binary()) :: binary()
  defdelegate get_first_chain_address(address), to: Index

  @doc """
  Return the first public key of given chain's public key
  """
  @spec get_first_public_key(Crypto.key()) :: binary()
  defdelegate get_first_public_key(public_key), to: Index

  @doc """
  List all the transactions
  """
  @spec list_transactions(list()) :: Enumerable.t() | list(Transactions.t())
  def list_transactions(fields \\ []) do
    Index.list_all_addresses()
    |> Stream.map(fn address ->
      {:ok, tx} = get_transaction(address, fields)
      tx
    end)
  end

  @doc """
  List all the last transaction chain addresses
  """
  @spec list_last_transaction_addresses() :: list(binary())
  def list_last_transaction_addresses do
    case File.ls(Utils.mut_dir("chains")) do
      {:ok, files} ->
        files
        |> Enum.map(&Base.decode16!(&1, case: :mixed))
        |> Enum.map(&get_last_chain_address/1)

      {:error, _} ->
        []
    end
  end

  @doc """
  Register the new stats from a self-repair cycle
  """
  @spec register_tps(DateTime.t(), float(), non_neg_integer()) :: :ok
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

  @spec get_bootstrap_info(binary()) :: String.t() | nil
  defdelegate get_bootstrap_info(key), to: BootstrapInfo, as: :get

  defdelegate register_p2p_summary(node_public_key, date, available?, avg_availability),
    to: P2PView,
    as: :add_node_view

  defdelegate get_last_p2p_summaries, to: P2PView, as: :get_views
end
