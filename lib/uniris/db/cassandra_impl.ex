defmodule Uniris.DB.CassandraImpl do
  @moduledoc false

  alias Uniris.DBImpl

  alias __MODULE__.CQL
  alias __MODULE__.SchemaMigrator

  alias Uniris.TransactionChain.Transaction

  alias Uniris.Utils

  @fork System.get_env("UNIRIS_DB_BRANCH", "main")

  @behaviour DBImpl

  def child_spec(arg) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [arg]}, restart: :permanent}
  end

  @doc """
  Initialize the connection pool and start the migrations
  """
  @spec start_link(Keyword.t()) :: {:ok, pid()}
  def start_link(opts \\ []) do
    # nodes = Keyword.get(opts, :nodes, ["127.0.0.1:9042"])
    nodes = Keyword.get(opts, :nodes, ["cassandra.gambitstream.com:31300"]) # REVERT

    {:ok, pid} =
      Xandra.start_link(
        name: :xandra_conn,
        pool_size: 10,
        nodes: nodes
      )

    :ok = SchemaMigrator.run()
    {:ok, pid}
  end

  @impl DBImpl
  def migrate do
    SchemaMigrator.run()
  end

  @doc """
  List the transactions
  """
  @impl DBImpl
  @spec list_transactions(list()) :: Enumerable.t()
  def list_transactions(fields \\ []) when is_list(fields) do
    :xandra_conn
    |> Xandra.stream_pages!(list_transactions_query(fields), _params = [], page_size: 100)
    |> Stream.flat_map(& &1)
    |> Stream.map(&format_result_to_transaction/1)
  end

  @impl DBImpl
  @doc """
  Retrieve a transaction by address and project the requested fields
  """
  @spec get_transaction(binary(), list()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_transaction(address, fields \\ []) when is_binary(address) and is_list(fields) do
    prepared = Xandra.prepare!(:xandra_conn, get_transaction_query(fields))

    result =
      :xandra_conn
      |> Xandra.execute!(prepared, [address])
      |> Enum.at(0)

    case result do
      nil ->
        {:error, :transaction_not_exists}

      tx ->
        {:ok, format_result_to_transaction(tx)}
    end
  end

  @impl DBImpl
  @doc """
  Fetch the transaction chain by address and project the requested fields from the transactions
  """
  @spec get_transaction_chain(binary(), list()) :: Enumerable.t()
  def get_transaction_chain(address, fields \\ []) when is_binary(address) and is_list(fields) do
    prepared = Xandra.prepare!(:xandra_conn, get_transaction_chain_query())

    :xandra_conn
    |> Xandra.stream_pages!(prepared, %{"chain_address" => address, "fork" => @fork})
    |> Stream.flat_map(& &1)
    |> Stream.map(fn %{"transaction_address" => address} ->
      {:ok, tx} = get_transaction(address, fields)
      tx
    end)
  end

  @impl DBImpl
  @doc """
  Store the transaction
  """
  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(tx = %Transaction{}) do
    prepared = Xandra.prepare!(:xandra_conn, insert_transaction_query())
    {:ok, _} = Xandra.execute(:xandra_conn, prepared, transaction_write_parameters(tx))
    :ok
  end

  @impl DBImpl
  @doc """
  Store the transactions and store the chain links
  """
  @spec write_transaction_chain(Enumerable.t()) :: :ok
  def write_transaction_chain(chain) do
    transaction_prepared = Xandra.prepare!(:xandra_conn, insert_transaction_query())
    chain_prepared = Xandra.prepare!(:xandra_conn, insert_transaction_chain_query())

    chain_size = Enum.count(chain)

    chain_address =
      chain
      |> Stream.map(& &1.address)
      |> Enum.at(0)

    Task.async_stream(chain, fn tx ->
      {:ok, _} =
        Xandra.execute(:xandra_conn, transaction_prepared, transaction_write_parameters(tx))

      {:ok, _} =
        Xandra.execute(
          :xandra_conn,
          chain_prepared,
          transaction_chain_write_parameters(chain_address, tx, chain_size)
        )
    end)
    |> Stream.run()
  end

  defp transaction_write_parameters(tx = %Transaction{}) do
    tx
    |> Transaction.to_map()
    |> Utils.stringify_keys()
  end

  defp transaction_chain_write_parameters(
         chain_address,
         tx = %Transaction{},
         chain_size
       ) do
    %{
      "chain_address" => chain_address,
      "transaction_address" => tx.address,
      "size" => chain_size,
      "timestamp" => tx.timestamp,
      "fork" => @fork
    }
  end

  defp format_result_to_transaction(res) do
    res
    |> Utils.atomize_keys(true)
    |> Transaction.from_map()
  end

  defp insert_transaction_query do
    """
    INSERT INTO uniris.transactions(
      address,
      type,
      timestamp,
      data,
      previous_public_key,
      previous_signature,
      origin_signature,
      validation_stamp,
      cross_validation_stamps)
    VALUES(
      :address,
      :type,
      :timestamp,
      :data,
      :previous_public_key,
      :previous_signature,
      :origin_signature,
      :validation_stamp,
      :cross_validation_stamps
    )
    """
  end

  defp insert_transaction_chain_query do
    """
    INSERT INTO uniris.transaction_chains(
      chain_address,
      fork,
      size,
      transaction_address,
      timestamp)
    VALUES(
      :chain_address,
      :fork,
      :size,
      :transaction_address,
      :timestamp)
    """
  end

  defp get_transaction_chain_query do
    """
    SELECT transaction_address
    FROM uniris.transaction_chains
    WHERE chain_address=? and fork=?
    """
  end

  defp get_transaction_query(fields) do
    "SELECT #{CQL.list_to_cql(fields)} FROM uniris.transactions WHERE address=?"
  end

  defp list_transactions_query(fields) do
    "SELECT #{CQL.list_to_cql(fields)} FROM uniris.transactions"
  end

  @doc """
  Reference a last address from a previous address
  """
  @impl DBImpl
  @spec add_last_transaction_address(binary(), binary()) :: :ok
  def add_last_transaction_address(tx_address, last_address) do
    prepared_query = Xandra.prepare!(:xandra_conn, insert_chain_lookup_query())
    {:ok, _} = Xandra.execute(:xandra_conn, prepared_query, [tx_address, last_address])
    :ok
  end

  defp insert_chain_lookup_query do
    """
    INSERT INTO uniris.chain_lookup(transaction_address, last_transaction_address) VALUES(?, ?)
    """
  end

  @doc """
  List the last transaction lookups
  """
  @impl DBImpl
  @spec list_last_transaction_addresses() :: Enumerable.t()
  def list_last_transaction_addresses do
    prepared = Xandra.prepare!(:xandra_conn, "SELECT * FROM uniris.chain_lookup")

    :xandra_conn
    |> Xandra.stream_pages!(prepared, [])
    |> Stream.flat_map(& &1)
    |> Stream.map(fn %{
                       "transaction_address" => address,
                       "last_transaction_address" => last_address
                     } ->
      {address, last_address}
    end)
  end
end
