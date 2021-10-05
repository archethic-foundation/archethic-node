defmodule ArchEthic.DB.CassandraImpl do
  @moduledoc false

  alias ArchEthic.Crypto

  alias ArchEthic.DB

  alias __MODULE__.CQL
  alias __MODULE__.QueryProducer
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
    "SELECT #{CQL.list_to_cql(fields)} FROM archethic.transactions"
    |> QueryProducer.add_query([], true)
    |> Stream.map(&format_result_to_transaction/1)
  end

  @impl DB
  @doc """
  Retrieve a transaction by address and project the requested fields
  """
  @spec get_transaction(binary(), list()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_transaction(address, fields \\ []) when is_binary(address) and is_list(fields) do
    start = System.monotonic_time()

    result =
      QueryProducer.add_query(
        "SELECT #{CQL.list_to_cql(fields)} FROM archethic.transactions WHERE address=?",
        [address]
      )

    case Enum.at(result, 0) do
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
  def get_transaction_chain(address, fields \\ []) when is_binary(address) and is_list(fields) do
    start = System.monotonic_time()

    chain =
      1..4
      |> Task.async_stream(fn bucket ->
        "SELECT #{CQL.list_to_cql(fields)} FROM archethic.transactions WHERE chain_address=? and bucket=?"
        |> QueryProducer.add_query([address, bucket], true)
        |> Enum.map(&format_result_to_transaction/1)
      end)
      |> Stream.map(fn {:ok, res} -> res end)
      |> Enum.flat_map(& &1)

    :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
      query: "get_transaction_chain"
    })

    chain
  end

  @impl DB
  @doc """
  Store the transaction
  """
  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(tx = %Transaction{address: address}) do
    do_write_transaction(tx, address)
  end

  @impl DB
  @doc """
  Store the transaction into the given chain address
  """
  @spec write_transaction(Transaction.t(), binary()) :: :ok
  def write_transaction(tx = %Transaction{}, chain_address) when is_binary(chain_address) do
    do_write_transaction(tx, chain_address)
  end

  defp do_write_transaction(
         tx = %Transaction{},
         chain_address
       ) do
    %{
      "chain_address" => chain_address,
      "bucket" => bucket,
      "timestamp" => timestamp,
      "version" => version,
      "address" => address,
      "type" => type,
      "data" => data,
      "previous_public_key" => previous_public_key,
      "previous_signature" => previous_signature,
      "origin_signature" => origin_signature,
      "validation_stamp" => validation_stamp,
      "cross_validation_stamps" => cross_validation_stamps
    } = encode_transaction_to_parameters(tx, chain_address)

    start = System.monotonic_time()

    "INSERT INTO archethic.transactions (chain_address, bucket, timestamp, version, address, type, data, previous_public_key, previous_signature, origin_signature, validation_stamp, cross_validation_stamps) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    |> QueryProducer.add_query([
      chain_address,
      bucket,
      timestamp,
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

    "INSERT INTO archethic.transaction_type_lookup(type, address, timestamp) VALUES(?, ?, ?)"
    |> QueryProducer.add_query([type, address, timestamp])

    :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
      query: "write_transaction"
    })

    :ok
  end

  defp encode_transaction_to_parameters(
         tx = %Transaction{validation_stamp: %ValidationStamp{timestamp: timestamp}},
         chain_address
       ) do
    tx
    |> Transaction.to_map()
    |> Utils.stringify_keys()
    |> Map.put("chain_address", chain_address)
    |> Map.put("bucket", bucket_from_date(timestamp))
    |> Map.put("timestamp", timestamp)
  end

  @impl DB
  @doc """
  Store the transactions and store the chain links
  """
  @spec write_transaction_chain(Enumerable.t()) :: :ok
  def write_transaction_chain(chain) do
    %Transaction{
      address: chain_address,
      previous_public_key: chain_public_key
    } = Enum.at(chain, 0)

    start = System.monotonic_time()

    statement_by_first_address =
      "INSERT INTO archethic.chain_lookup_by_first_address(last_transaction_address, genesis_transaction_address) VALUES (?, ?)"

    statement_by_first_key =
      "INSERT INTO archethic.chain_lookup_by_first_key(last_key, genesis_key) VALUES (?, ?)"

    statement_by_last_address =
      "INSERT INTO archethic.chain_lookup_by_last_address(transaction_address, last_transaction_address, timestamp) VALUES(?, ?, ?)"

    Stream.each(
      chain,
      fn tx = %Transaction{
           address: tx_address,
           validation_stamp: %ValidationStamp{timestamp: tx_timestamp},
           previous_public_key: tx_public_key
         } ->
        do_write_transaction(tx, chain_address)

        QueryProducer.add_query(statement_by_first_address, [chain_address, tx_address])

        QueryProducer.add_query(statement_by_first_key, [chain_public_key, tx_public_key])

        QueryProducer.add_query(statement_by_last_address, [
          Transaction.previous_address(tx),
          chain_address,
          tx_timestamp
        ])
      end
    )
    |> Stream.run()

    :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
      query: "write_transaction_chain"
    })

    :ok
  end

  defp bucket_from_date(%DateTime{month: month}) do
    div(month + 2, 3)
  end

  defp format_result_to_transaction(res) do
    res
    |> Map.drop(["bucket", "chain_address", "timestamp"])
    |> Utils.atomize_keys(true)
    |> Transaction.from_map()
  end

  @doc """
  Reference a last address from a previous address
  """
  @impl DB
  @spec add_last_transaction_address(binary(), binary(), DateTime.t()) :: :ok
  def add_last_transaction_address(tx_address, last_address, timestamp = %DateTime{}) do
    QueryProducer.add_query(
      "INSERT INTO archethic.chain_lookup_by_last_address(transaction_address, last_transaction_address, timestamp) VALUES(?, ?, ?)",
      [tx_address, last_address, timestamp]
    )

    :ok
  end

  @doc """
  List the last transaction lookups
  """
  @impl DB
  @spec list_last_transaction_addresses() :: Enumerable.t()
  def list_last_transaction_addresses do
    "SELECT last_transaction_address FROM archethic.chain_lookup_by_last_address PER PARTITION LIMIT 1"
    |> QueryProducer.add_query([], true)
    |> Stream.map(&Map.get(&1, "last_transaction_address"))
    |> Stream.uniq()
  end

  @impl DB
  @spec chain_size(binary()) :: non_neg_integer()
  def chain_size(address) do
    "SELECT COUNT(*) as size FROM archethic.transactions WHERE chain_address=?"
    |> QueryProducer.add_query([address])
    |> Enum.at(0, %{})
    |> Map.get("size", 0)
  end

  @impl DB
  @spec list_transactions_by_type(type :: Transaction.transaction_type(), fields :: list()) ::
          Enumerable.t()
  def list_transactions_by_type(type, fields \\ []) do
    "SELECT address FROM archethic.transaction_type_lookup WHERE type=?"
    |> QueryProducer.add_query([Atom.to_string(type)], true)
    |> Stream.map(fn %{"address" => address} ->
      {:ok, tx} = get_transaction(address, fields)
      tx
    end)
  end

  @impl DB
  @spec count_transactions_by_type(type :: Transaction.transaction_type()) :: non_neg_integer()
  def count_transactions_by_type(type) do
    "SELECT COUNT(address) as nb FROM archethic.transaction_type_lookup WHERE type=?"
    |> QueryProducer.add_query([Atom.to_string(type)])
    |> Enum.at(0, %{})
    |> Map.get("nb", 0)
  end

  @doc """
  Get the last transaction address of a chain
  """
  @impl DB
  @spec get_last_chain_address(binary()) :: binary()
  def get_last_chain_address(address) do
    "SELECT last_transaction_address FROM archethic.chain_lookup_by_last_address WHERE transaction_address = ?"
    |> QueryProducer.add_query([address])
    |> Enum.at(0, %{})
    |> Map.get("last_transaction_address", address)
  end

  @doc """
  Get the last transaction address of a chain before a given certain datetime
  """
  @impl DB
  @spec get_last_chain_address(binary(), DateTime.t()) :: binary()
  def get_last_chain_address(address, datetime = %DateTime{}) do
    "SELECT last_transaction_address FROM archethic.chain_lookup_by_last_address WHERE transaction_address = ? and timestamp <= ?"
    |> QueryProducer.add_query([address, datetime])
    |> Enum.at(0, %{})
    |> Map.get("last_transaction_address", address)
  end

  @doc """
  Get the first transaction address for a chain
  """
  @impl DB
  @spec get_first_chain_address(binary()) :: binary()
  def get_first_chain_address(address) when is_binary(address) do
    "SELECT genesis_transaction_address FROM archethic.chain_lookup_by_first_address WHERE last_transaction_address=?"
    |> QueryProducer.add_query([address])
    |> Enum.at(0, %{})
    |> Map.get("genesis_transaction_address", address)
  end

  @doc """
  Get the first public key of of transaction chain
  """
  @impl DB
  @spec get_first_public_key(Crypto.key()) :: Crypto.key()
  def get_first_public_key(previous_public_key) when is_binary(previous_public_key) do
    "SELECT genesis_key FROM archethic.chain_lookup_by_first_key WHERE last_key=?"
    |> QueryProducer.add_query([previous_public_key])
    |> Enum.at(0, %{})
    |> Map.get("genesis_key", previous_public_key)
  end

  @doc """
  Return the latest TPS record
  """
  @impl DB
  @spec get_latest_tps :: float()
  def get_latest_tps do
    "SELECT tps FROM archethic.network_stats_by_date"
    |> QueryProducer.add_query()
    |> Enum.at(0, %{})
    |> Map.get("tps", 0.0)
  end

  @doc """
  Returns the number of transactions
  """
  @impl DB
  @spec get_nb_transactions() :: non_neg_integer()
  def get_nb_transactions do
    "SELECT nb_transactions FROM archethic.network_stats_by_date"
    |> QueryProducer.add_query([], true)
    |> Enum.reduce(0, fn %{"nb_transactions" => nb_transactions}, acc -> nb_transactions + acc end)
  end

  @doc """
  Register a new TPS for the given date
  """
  @impl DB
  @spec register_tps(DateTime.t(), float(), non_neg_integer()) :: :ok
  def register_tps(date = %DateTime{}, tps, nb_transactions)
      when is_float(tps) and tps >= 0.0 and is_integer(nb_transactions) and nb_transactions >= 0 do
    QueryProducer.add_query(
      "INSERT INTO archethic.network_stats_by_date (date, tps, nb_transactions) VALUES (?, ?, ?)",
      [date, tps, nb_transactions]
    )

    :ok
  end

  @doc """
  Determines if the transaction address exists
  """
  @impl DB
  @spec transaction_exists?(binary()) :: boolean()
  def transaction_exists?(address) when is_binary(address) do
    count =
      "SELECT COUNT(address) as count FROM archethic.transactions WHERE chain_address=?"
      |> QueryProducer.add_query([address])
      |> Enum.at(0, %{})
      |> Map.get("count", 0)

    count > 0
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
    QueryProducer.add_query(
      "INSERT INTO archethic.p2p_summary_by_node (node_public_key, date, available, average_availability) VALUES (?, ?, ?, ?)",
      [
        node_public_key,
        date,
        available?,
        avg_availability
      ]
    )
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
    "SELECT node_public_key, available, average_availability FROM archethic.p2p_summary_by_node PER PARTITION LIMIT 1"
    |> QueryProducer.add_query([], true)
    |> Stream.map(fn %{
                       "node_public_key" => node_public_key,
                       "available" => available?,
                       "average_availability" => avg_availability
                     } ->
      {node_public_key, {available?, avg_availability}}
    end)
    |> Enum.into(%{})
  end
end
