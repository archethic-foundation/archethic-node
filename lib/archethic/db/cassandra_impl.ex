defmodule ArchEthic.DB.CassandraImpl do
  @moduledoc false

  alias ArchEthic.Crypto

  alias ArchEthic.DB

  alias __MODULE__.CQL
  alias __MODULE__.SchemaMigrator
  alias __MODULE__.Supervisor, as: CassandraSupervisor

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp

  alias ArchEthic.Utils

  @behaviour DB

  defdelegate child_spec(arg), to: CassandraSupervisor

  @impl DB
  def migrate do
    SchemaMigrator.run()
  end

  @doc """
  List the transactions
  """
  @impl DB
  @spec list_transactions(list()) :: Enumerable.t()
  def list_transactions(fields \\ []) when is_list(fields) do
    Xandra.stream_pages!(
      :xandra_conn,
      "SELECT #{CQL.list_to_cql(fields)} FROM archethic.transactions",
      [],
      page_size: 10
    )
    |> Stream.flat_map(& &1)
    |> Stream.map(&format_result_to_transaction/1)
    |> Enum.to_list()
  end

  @impl DB
  @doc """
  Retrieve a transaction by address and project the requested fields
  """
  @spec get_transaction(binary(), list()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_transaction(address, fields \\ []) when is_binary(address) and is_list(fields) do
    do_get_transaction(:xandra_conn, address, fields)
  end

  defp do_get_transaction(conn, address, fields) do
    start = System.monotonic_time()

    prepared =
      Xandra.prepare!(
        conn,
        "SELECT #{CQL.list_to_cql(fields)} FROM archethic.transactions WHERE address=?"
      )

    results = Xandra.execute!(conn, prepared, [address])

    case Enum.at(results, 0) do
      nil ->
        {:error, :transaction_not_exists}

      tx ->
        :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
          query: "get_transaction"
        })

        {:ok, format_result_to_transaction(tx)}
    end
  end

  @impl DB
  @doc """
  Fetch the transaction chain by address and project the requested fields from the transactions
  """
  @spec get_transaction_chain(binary(), list()) :: Enumerable.t()
  def get_transaction_chain(
        address,
        options \\ [],
        fields \\ []
      )
      when is_binary(address) and is_list(fields) and is_list(options) do
    start = System.monotonic_time()
    {query, query_params} = get_transaction_chain_query(address, options)
    prepared_statement = Xandra.prepare!(:xandra_conn, query)

    execute_options = get_transaction_chain_options(address, options)
    # edgecases/errors here are handled by process crash
    {:ok, page} = Xandra.execute(:xandra_conn, prepared_statement, query_params, execute_options)
    paging_state = page.paging_state

    addresses_to_fetch =
      Enum.map(page, fn %{"transaction_address" => tx_address} -> tx_address end)

    chain =
      addresses_to_fetch
      |> chunk_get_transaction(fields)

    # |> Enum.flat_map(& &1)

    :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
      query: "get_transaction_chain"
    })

    [chain: chain, page: paging_state]
  end

  defp get_transaction_chain_query(address, []) do
    {" SELECT transaction_address   FROM archethic.transaction_chains WHERE chain_address = ? ",
     [address]}
  end

  defp get_transaction_chain_query(address, after_time: nil, page: _current_page_state) do
    {" SELECT transaction_address   FROM archethic.transaction_chains WHERE chain_address = ? ",
     [address]}
  end

  defp get_transaction_chain_query(address,
         after_time: %DateTime{} = after_time,
         page: _current_page_state
       ) do
    {" SELECT transaction_address FROM archethic.transaction_chains WHERE chain_address = ? AND transaction_timestamp >=  ? ",
     [address, after_time]}
  end

  defp get_transaction_chain_options(_address, []),
    do: [page_size: 10]

  defp get_transaction_chain_options(_address, after_time: _after_time, page: nil),
    do: [page_size: 10]

  defp get_transaction_chain_options(_address, after_time: _after_time, page: current_page_state)
       when is_binary(current_page_state),
       do: [page_size: 10, paging_state: current_page_state]

  defp chunk_get_transaction(addresses, fields) do
    Xandra.run(:xandra_conn, fn conn ->
      Enum.map(addresses, fn address ->
        {:ok, tx} = do_get_transaction(conn, address, fields)
        tx
      end)
    end)
  end

  @impl DB
  @doc """
  Store the transaction
  """
  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(
        tx = %Transaction{
          address: tx_address,
          validation_stamp: %ValidationStamp{timestamp: tx_timestamp}
        }
      ) do
    Xandra.run(:xandra_conn, fn conn ->
      do_write_transaction(conn, tx)
      add_transaction_to_chain(conn, tx_address, tx_timestamp, tx_address)
    end)
  end

  @impl DB
  @doc """
  Store the transaction into the given chain address
  """
  @spec write_transaction(Transaction.t(), binary()) :: :ok
  def write_transaction(
        tx = %Transaction{
          address: tx_address,
          validation_stamp: %ValidationStamp{timestamp: tx_timestamp}
        },
        chain_address
      )
      when is_binary(chain_address) do
    Xandra.run(:xandra_conn, fn conn ->
      do_write_transaction(conn, tx)
      add_transaction_to_chain(conn, tx_address, tx_timestamp, chain_address)
    end)
  end

  defp do_write_transaction(conn, tx = %Transaction{}) do
    %{
      "version" => version,
      "address" => address,
      "type" => type,
      "data" => data,
      "previous_public_key" => previous_public_key,
      "previous_signature" => previous_signature,
      "origin_signature" => origin_signature,
      "validation_stamp" => validation_stamp = %{"timestamp" => timestamp},
      "cross_validation_stamps" => cross_validation_stamps
    } = encode_transaction_to_parameters(tx)

    start = System.monotonic_time()

    transaction_insert_prepared =
      Xandra.prepare!(
        conn,
        "INSERT INTO archethic.transactions (version, address, type, data, previous_public_key, previous_signature, origin_signature, validation_stamp, cross_validation_stamps) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)"
      )

    transaction_insert_type_prepared =
      Xandra.prepare!(
        conn,
        "INSERT INTO archethic.transaction_type_lookup(type, address, timestamp) VALUES(?, ?, ?)"
      )

    Xandra.execute!(conn, transaction_insert_prepared, [
      version,
      address,
      type,
      data,
      previous_public_key,
      previous_signature,
      origin_signature,
      validation_stamp,
      cross_validation_stamps
    ])

    Xandra.execute!(conn, transaction_insert_type_prepared, [
      type,
      address,
      timestamp
    ])

    :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
      query: "write_transaction"
    })

    :ok
  end

  defp encode_transaction_to_parameters(tx = %Transaction{}) do
    tx
    |> Transaction.to_map()
    |> Utils.stringify_keys()
  end

  @impl DB
  @doc """
  Store the transactions and store the chain links
  """
  @spec write_transaction_chain(Enumerable.t()) :: :ok
  def write_transaction_chain(chain) do
    %Transaction{
      address: chain_address,
      previous_public_key: chain_public_key,
      validation_stamp: %ValidationStamp{timestamp: chain_timestamp}
    } = Enum.at(chain, 0)

    start = System.monotonic_time()

    Xandra.run(:xandra_conn, fn conn ->
      insert_lookup_by_first_address_prepared =
        Xandra.prepare!(
          conn,
          "INSERT INTO archethic.chain_lookup_by_first_address(last_transaction_address, genesis_transaction_address) VALUES (?, ?)"
        )

      insert_lookup_by_first_key_prepared =
        Xandra.prepare!(
          conn,
          "INSERT INTO archethic.chain_lookup_by_first_key(last_key, genesis_key) VALUES (?, ?)"
        )

      insert_lookup_by_last_address_prepared =
        Xandra.prepare!(
          conn,
          "INSERT INTO archethic.chain_lookup_by_last_address(transaction_address, last_transaction_address, timestamp) VALUES(?, ?, ?)"
        )

      Stream.each(
        chain,
        fn tx = %Transaction{
             address: tx_address,
             validation_stamp: %ValidationStamp{timestamp: tx_timestamp},
             previous_public_key: tx_public_key
           } ->
          do_write_transaction(conn, tx)

          Xandra.execute!(conn, insert_lookup_by_first_address_prepared, [
            chain_address,
            tx_address
          ])

          Xandra.execute!(conn, insert_lookup_by_first_key_prepared, [
            chain_public_key,
            tx_public_key
          ])

          Xandra.execute!(conn, insert_lookup_by_last_address_prepared, [
            Transaction.previous_address(tx),
            chain_address,
            chain_timestamp
          ])

          add_transaction_to_chain(conn, tx_address, tx_timestamp, chain_address)
        end
      )
      |> Stream.run()

      :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
        query: "write_transaction_chain"
      })

      :ok
    end)
  end

  defp add_transaction_to_chain(conn, tx_address, tx_timestamp, chain_address) do
    prepared =
      Xandra.prepare!(
        conn,
        "INSERT INTO archethic.transaction_chains(chain_address, transaction_address, transaction_timestamp) VALUES( ?, ?, ?)"
      )

    Xandra.execute!(conn, prepared, [
      chain_address,
      tx_address,
      tx_timestamp
    ])

    :ok
  end

  defp format_result_to_transaction(res) do
    res
    |> Map.drop(["chain_address", "timestamp"])
    |> Utils.atomize_keys(true)
    |> Transaction.from_map()
  end

  @doc """
  Reference a last address from a previous address
  """
  @impl DB
  @spec add_last_transaction_address(binary(), binary(), DateTime.t()) :: :ok
  def add_last_transaction_address(tx_address, last_address, timestamp = %DateTime{}) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "INSERT INTO archethic.chain_lookup_by_last_address(transaction_address, last_transaction_address, timestamp) VALUES(?, ?, ?)"
      )

    Xandra.execute!(:xandra_conn, prepared, [tx_address, last_address, timestamp])

    :ok
  end

  @doc """
  List the last transaction lookups
  """
  @impl DB
  @spec list_last_transaction_addresses() :: Enumerable.t()
  def list_last_transaction_addresses do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT last_transaction_address FROM archethic.chain_lookup_by_last_address PER PARTITION LIMIT 1"
      )

    :xandra_conn
    |> Xandra.stream_pages!(prepared, [], page_size: 10)
    |> Stream.flat_map(& &1)
    |> Stream.map(&Map.get(&1, "last_transaction_address"))
    |> Enum.uniq()
  end

  @impl DB
  @spec chain_size(binary()) :: non_neg_integer()
  def chain_size(address) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT COUNT(*) as size FROM archethic.transaction_chains WHERE chain_address=? "
      )

    [size] =
      :xandra_conn
      |> Xandra.execute!(prepared, [address])
      |> Enum.map(fn %{"size" => size} -> size end)

    size
  end

  @impl DB
  @spec list_transactions_by_type(type :: Transaction.transaction_type(), fields :: list()) ::
          Enumerable.t()
  def list_transactions_by_type(type, fields \\ []) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT address FROM archethic.transaction_type_lookup WHERE type=?"
      )

    :xandra_conn
    |> Xandra.stream_pages!(prepared, [Atom.to_string(type)], page_size: 10)
    |> Stream.flat_map(& &1)
    |> Stream.map(fn %{"address" => address} ->
      {:ok, tx} = get_transaction(address, fields)
      tx
    end)
    |> Enum.to_list()
  end

  @impl DB
  @spec count_transactions_by_type(type :: Transaction.transaction_type()) :: non_neg_integer()
  def count_transactions_by_type(type) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT COUNT(address) as nb FROM archethic.transaction_type_lookup WHERE type=?"
      )

    :xandra_conn
    |> Xandra.execute!(prepared, [Atom.to_string(type)])
    |> Enum.at(0, %{})
    |> Map.get("nb", 0)
  end

  @doc """
  Get the last transaction address of a chain
  """
  @impl DB
  @spec get_last_chain_address(binary()) :: binary()
  def get_last_chain_address(address) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT last_transaction_address FROM archethic.chain_lookup_by_last_address WHERE transaction_address = ? PER PARTITION LIMIT 1"
      )

    :xandra_conn
    |> Xandra.execute!(prepared, [address])
    |> Enum.at(0, %{})
    |> Map.get("last_transaction_address", address)
  end

  @doc """
  Get the last transaction address of a chain before a given certain datetime
  """
  @impl DB
  @spec get_last_chain_address(binary(), DateTime.t()) :: binary()
  def get_last_chain_address(address, datetime = %DateTime{}) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT last_transaction_address FROM archethic.chain_lookup_by_last_address WHERE transaction_address = ? and timestamp <= ? PER PARTITION LIMIT 1"
      )

    :xandra_conn
    |> Xandra.execute!(prepared, [address, datetime])
    |> Enum.at(0, %{})
    |> Map.get("last_transaction_address", address)
  end

  @doc """
  Get the first transaction address for a chain
  """
  @impl DB
  @spec get_first_chain_address(binary()) :: binary()
  def get_first_chain_address(address) when is_binary(address) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT genesis_transaction_address FROM archethic.chain_lookup_by_first_address WHERE last_transaction_address=?"
      )

    :xandra_conn
    |> Xandra.execute!(prepared, [address])
    |> Enum.at(0, %{})
    |> Map.get("genesis_transaction_address", address)
  end

  @doc """
  Get the first public key of of transaction chain
  """
  @impl DB
  @spec get_first_public_key(Crypto.key()) :: Crypto.key()
  def get_first_public_key(previous_public_key) when is_binary(previous_public_key) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT genesis_key FROM archethic.chain_lookup_by_first_key WHERE last_key=?"
      )

    :xandra_conn
    |> Xandra.execute!(prepared, [previous_public_key])
    |> Enum.at(0, %{})
    |> Map.get("genesis_key", previous_public_key)
  end

  @doc """
  Return the latest TPS record
  """
  @impl DB
  @spec get_latest_tps :: float()
  def get_latest_tps do
    prepared = Xandra.prepare!(:xandra_conn, "SELECT tps FROM archethic.network_stats_by_date")

    :xandra_conn
    |> Xandra.execute!(prepared)
    |> Enum.at(0, %{})
    |> Map.get("tps", 0.0)
  end

  @doc """
  Returns the number of transactions
  """
  @impl DB
  @spec get_nb_transactions() :: non_neg_integer()
  def get_nb_transactions do
    prepared =
      Xandra.prepare!(:xandra_conn, "SELECT nb_transactions FROM archethic.network_stats_by_date")

    :xandra_conn
    |> Xandra.stream_pages!(prepared, [], page_size: 100)
    |> Stream.flat_map(& &1)
    |> Enum.reduce(0, fn %{"nb_transactions" => nb_transactions}, acc -> nb_transactions + acc end)
  end

  @doc """
  Register a new TPS for the given date
  """
  @impl DB
  @spec register_tps(DateTime.t(), float(), non_neg_integer()) :: :ok
  def register_tps(date = %DateTime{}, tps, nb_transactions)
      when is_float(tps) and tps >= 0.0 and is_integer(nb_transactions) and nb_transactions >= 0 do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "INSERT INTO archethic.network_stats_by_date (date, tps, nb_transactions) VALUES (?, ?, ?)"
      )

    Xandra.execute!(:xandra_conn, prepared, [date, tps, nb_transactions])

    :ok
  end

  @doc """
  Determines if the transaction address exists
  """
  @impl DB
  @spec transaction_exists?(binary()) :: boolean()
  def transaction_exists?(address) when is_binary(address) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT COUNT(*) as count FROM archethic.transactions WHERE address=?"
      )

    result = Xandra.execute!(:xandra_conn, prepared, [address])

    case Enum.to_list(result) do
      [%{"count" => 0}] ->
        false

      [%{"count" => 1}] ->
        true
    end
  end

  @doc """
  Register the P2P summary for the given node and date
  """
  @impl DB
  @spec register_p2p_summary(
          node_public_key :: Crypto.key(),
          date :: DateTime.t(),
          available? :: boolean(),
          average_availability :: float()
        ) :: :ok
  def register_p2p_summary(
        node_public_key,
        date = %DateTime{},
        available?,
        avg_availability
      ) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "INSERT INTO archethic.p2p_summary_by_node (node_public_key, date, available, average_availability) VALUES (?, ?, ?, ?)"
      )

    Xandra.execute!(:xandra_conn, prepared, [
      node_public_key,
      date,
      available?,
      Float.round(avg_availability, 2)
    ])

    :ok
  end

  @doc """
  Get the last p2p summaries
  """
  @impl DB
  @spec get_last_p2p_summaries() :: %{
          (node_public_key :: Crypto.key()) =>
            {available? :: boolean(), average_availability :: float()}
        }
  def get_last_p2p_summaries do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT node_public_key, available, average_availability FROM archethic.p2p_summary_by_node PER PARTITION LIMIT 1"
      )

    :xandra_conn
    |> Xandra.execute!(prepared)
    |> Stream.map(fn %{
                       "node_public_key" => node_public_key,
                       "available" => available?,
                       "average_availability" => avg_availability
                     } ->
      {node_public_key, {available?, Float.round(avg_availability, 2)}}
    end)
    |> Enum.into(%{})
  end

  @impl DB
  @spec get_bootstrap_info(String.t()) :: String.t() | nil
  def get_bootstrap_info(info) do
    prepared =
      Xandra.prepare!(:xandra_conn, "SELECT value FROM archethic.bootstrap_info WHERE name = ?")

    :xandra_conn
    |> Xandra.execute!(prepared, [info])
    |> Enum.at(0, %{})
    |> Map.get("value")
  end

  @impl DB
  @spec set_bootstrap_info(String.t(), String.t()) :: :ok
  def set_bootstrap_info(name, value) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "INSERT INTO archethic.bootstrap_info (name, value) VALUES(?, ?)"
      )

    :xandra_conn
    |> Xandra.execute!(prepared, [name, value])

    :ok
  end
end
