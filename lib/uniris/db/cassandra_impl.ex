defmodule Uniris.DB.CassandraImpl do
  @moduledoc false

  alias Uniris.Crypto

  alias Uniris.DBImpl

  alias __MODULE__.CQL
  alias __MODULE__.SchemaMigrator

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp

  alias Uniris.Utils

  @behaviour DBImpl

  def child_spec(arg) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [arg]}, restart: :permanent}
  end

  @doc """
  Initialize the connection pool and start the migrations
  """
  @spec start_link(Keyword.t()) :: {:ok, pid()}
  def start_link(opts \\ []) do
    nodes = Keyword.get(opts, :nodes, ["127.0.0.1:9042"])

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
    |> Xandra.stream_pages!(
      "SELECT #{CQL.list_to_cql(fields)} FROM uniris.transactions",
      _params = [],
      page_size: 100
    )
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
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT #{CQL.list_to_cql(fields)} FROM uniris.transactions WHERE address=?"
      )

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
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT transaction_address FROM uniris.transaction_chains WHERE chain_address=?"
      )

    :xandra_conn
    |> Xandra.stream_pages!(prepared, %{"chain_address" => address})
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
  def write_transaction(
        tx = %Transaction{
          address: address,
          type: type,
          previous_public_key: previous_public_key,
          validation_stamp: %ValidationStamp{timestamp: timestamp}
        }
      ) do
    query = """
    INSERT INTO uniris.transactions(
      address,
      type,
      data,
      previous_public_key,
      previous_signature,
      origin_signature,
      validation_stamp,
      cross_validation_stamps)
    VALUES(
      :address,
      :type,
      :data,
      :previous_public_key,
      :previous_signature,
      :origin_signature,
      :validation_stamp,
      :cross_validation_stamps
    )
    """

    prepared = Xandra.prepare!(:xandra_conn, query)

    Xandra.execute!(:xandra_conn, prepared, tx |> Transaction.to_map() |> Utils.stringify_keys())

    previous_address = Crypto.hash(previous_public_key)

    add_last_transaction_address(address, address, timestamp)
    add_last_transaction_address(previous_address, address, timestamp)

    prepared2 =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT last_transaction_address, timestamp FROM uniris.chain_lookup_by_last_address WHERE transaction_address = ?"
      )

    Xandra.execute!(:xandra_conn, prepared2, [address])
    |> Enum.map(fn %{"last_transaction_address" => addr, "timestamp" => timestamp} ->
      {addr, timestamp}
    end)
    |> Enum.reject(&(elem(&1, 0) == address))
    |> Enum.each(fn {addr, timestamp} ->
      add_last_transaction_address(previous_address, addr, timestamp)
    end)

    prepared3 =
      Xandra.prepare!(
        :xandra_conn,
        "INSERT INTO uniris.transaction_type_lookup(type, address, timestamp) VALUES(?, ?, ?)"
      )

    Xandra.execute!(:xandra_conn, prepared3, [Atom.to_string(type), address, timestamp])

    :ok
  end

  @impl DBImpl
  @doc """
  Store the transactions and store the chain links
  """
  @spec write_transaction_chain(Enumerable.t()) :: :ok
  def write_transaction_chain(chain) do
    chain_prepared =
      Xandra.prepare!(
        :xandra_conn,
        "INSERT INTO uniris.transaction_chains(chain_address, size, transaction_address, timestamp) VALUES(:chain_address, :size, :transaction_address, :timestamp)"
      )

    chain_size = Enum.count(chain)

    %Transaction{address: chain_address} = Enum.at(chain, 0)

    chain
    |> Stream.with_index()
    |> Stream.each(
      fn {tx = %Transaction{
            address: tx_address,
            previous_public_key: tx_previous_public_key,
            validation_stamp: %ValidationStamp{timestamp: tx_timestamp}
          }, index} ->
        write_transaction(tx)

        params = %{
          "chain_address" => chain_address,
          "transaction_address" => tx_address,
          "size" => chain_size,
          "timestamp" => tx_timestamp
        }

        {:ok, _} = Xandra.execute(:xandra_conn, chain_prepared, params)

        if index == chain_size - 1 do
          post_chain_process(tx_address, tx_previous_public_key, chain)
        end
      end
    )
    |> Stream.run()
  end

  defp post_chain_process(tx_address, tx_previous_public_key, chain) do
    chain_lookup_by_first_address_prepared =
      Xandra.prepare!(
        :xandra_conn,
        "INSERT INTO uniris.chain_lookup_by_first_address(last_transaction_address, genesis_transaction_address) VALUES (?, ?)"
      )

    chain_lookup_by_first_key_prepared =
      Xandra.prepare!(
        :xandra_conn,
        "INSERT INTO uniris.chain_lookup_by_first_key(last_key, genesis_key) VALUES (?, ?)"
      )

    Stream.map(chain, fn %Transaction{
                           address: address,
                           previous_public_key: current_previous_public_key
                         } ->
      Xandra.execute!(:xandra_conn, chain_lookup_by_first_address_prepared, [address, tx_address])

      Xandra.execute!(:xandra_conn, chain_lookup_by_first_key_prepared, [
        current_previous_public_key,
        tx_previous_public_key
      ])
    end)
    |> Stream.run()
  end

  defp format_result_to_transaction(res) do
    res
    |> Utils.atomize_keys(true)
    |> Transaction.from_map()
  end

  @doc """
  Reference a last address from a previous address
  """
  @impl DBImpl
  @spec add_last_transaction_address(binary(), binary(), DateTime.t()) :: :ok
  def add_last_transaction_address(tx_address, last_address, timestamp = %DateTime{}) do
    prepared_query =
      Xandra.prepare!(
        :xandra_conn,
        "INSERT INTO uniris.chain_lookup_by_last_address(transaction_address, last_transaction_address, timestamp) VALUES(?, ?, ?)"
      )

    Xandra.execute!(:xandra_conn, prepared_query, [tx_address, last_address, timestamp])
    :ok
  end

  @doc """
  List the last transaction lookups
  """
  @impl DBImpl
  @spec list_last_transaction_addresses() :: Enumerable.t()
  def list_last_transaction_addresses do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT * FROM uniris.chain_lookup_by_last_address PER PARTITION LIMIT 1"
      )

    :xandra_conn
    |> Xandra.stream_pages!(prepared, [])
    |> Stream.flat_map(& &1)
    |> Stream.map(fn %{
                       "transaction_address" => address,
                       "last_transaction_address" => last_address,
                       "timestamp" => timestamp
                     } ->
      {address, last_address, timestamp}
    end)
  end

  @impl DBImpl
  @spec chain_size(binary()) :: non_neg_integer()
  def chain_size(address) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT size FROM uniris.transaction_chains WHERE chain_address = ?"
      )

    :xandra_conn
    |> Xandra.execute!(prepared, [address])
    |> Enum.at(0, %{})
    |> Map.get("size", 0)
  end

  @impl DBImpl
  @spec list_transactions_by_type(type :: Transaction.transaction_type(), fields :: list()) ::
          Enumerable.t()
  def list_transactions_by_type(type, fields \\ []) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT address FROM uniris.transaction_type_lookup WHERE type = ?"
      )

    Xandra.stream_pages!(:xandra_conn, prepared, [Atom.to_string(type)])
    |> Stream.flat_map(& &1)
    |> Stream.map(fn %{"address" => address} ->
      {:ok, tx} = get_transaction(address, fields)
      tx
    end)
  end

  @impl DBImpl
  @spec count_transactions_by_type(type :: Transaction.transaction_type()) :: non_neg_integer()
  def count_transactions_by_type(type) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT COUNT(address) as nb FROM uniris.transaction_type_lookup WHERE type = ?"
      )

    :xandra_conn
    |> Xandra.execute!(prepared, [Atom.to_string(type)])
    |> Enum.at(0, %{})
    |> Map.get("nb", 0)
  end

  @doc """
  Get the last transaction address of a chain
  """
  @impl DBImpl
  @spec get_last_chain_address(binary()) :: binary()
  def get_last_chain_address(address) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT last_transaction_address FROM uniris.chain_lookup_by_last_address WHERE transaction_address = ?"
      )

    :xandra_conn
    |> Xandra.execute!(prepared, [address])
    |> Enum.at(0, %{})
    |> Map.get("last_transaction_address", address)
  end

  @doc """
  Get the last transaction address of a chain before a given certain datetime
  """
  @impl DBImpl
  @spec get_last_chain_address(binary(), DateTime.t()) :: binary()
  def get_last_chain_address(address, datetime = %DateTime{}) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT last_transaction_address FROM uniris.chain_lookup_by_last_address WHERE transaction_address = ? and timestamp <= ?"
      )

    :xandra_conn
    |> Xandra.execute!(prepared, [address, datetime])
    |> Enum.at(0, %{})
    |> Map.get("last_transaction_address", address)
  end

  @doc """
  Get the first transaction address for a chain
  """
  @impl DBImpl
  @spec get_first_chain_address(binary()) :: binary()
  def get_first_chain_address(address) when is_binary(address) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT genesis_transaction_address FROM uniris.chain_lookup_by_first_address WHERE last_transaction_address = ?"
      )

    :xandra_conn
    |> Xandra.execute!(prepared, [address])
    |> Enum.at(0, %{})
    |> Map.get("genesis_transaction_address", address)
  end

  @doc """
  Get the first public key of of transaction chain
  """
  @impl DBImpl
  @spec get_first_public_key(Crypto.key()) :: Crypto.key()
  def get_first_public_key(previous_public_key) when is_binary(previous_public_key) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT genesis_key FROM uniris.chain_lookup_by_first_key WHERE last_key = ?"
      )

    :xandra_conn
    |> Xandra.execute!(prepared, [previous_public_key])
    |> Enum.at(0, %{})
    |> Map.get("genesis_key", previous_public_key)
  end
end
