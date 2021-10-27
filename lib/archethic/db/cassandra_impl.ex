defmodule ArchEthic.DB.CassandraImpl do
  @moduledoc false

  alias ArchEthic.Crypto

  alias ArchEthic.DB

  alias __MODULE__.CQL
  alias __MODULE__.SchemaMigrator
  alias __MODULE__.Supervisor, as: CassandraSupervisor

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp

  @behaviour DB

  require Record

  Record.defrecord(:cql_query, Record.extract(:cql_query, from_lib: "cqerl/include/cqerl.hrl"))
  Record.defrecord(:cql_result, Record.extract(:cql_result, from_lib: "cqerl/include/cqerl.hrl"))

  Record.defrecord(
    :cql_query_batch,
    Record.extract(:cql_query_batch, from_lib: "cqerl/include/cqerl.hrl")
  )

  defdelegate child_spec(arg), to: CassandraSupervisor

  @impl DB
  def migrate do
    {:ok, client} = :cqerl.get_client({})
    SchemaMigrator.run(client)
  end

  @doc """
  List the transactions
  """
  @impl DB
  @spec list_transactions(list()) :: Enumerable.t()
  def list_transactions(fields \\ []) when is_list(fields) do
    {:ok, client} = :cqerl.get_client()

    Stream.resource(
      fn ->
        :cqerl.send_query(client, "SELECT #{CQL.list_to_cql(fields)} FROM archethic.transactions")
      end,
      fn
        :eof ->
          {:halt, :eof}

        ref ->
          receive do
            {:result, ^ref, result} ->
              rows = :cqerl.all_rows(result)

              case :cqerl.fetch_more_async(result) do
                :no_more_result ->
                  {rows, :eof}

                ref ->
                  {rows, ref}
              end
          end
      end,
      fn _ -> :ok end
    )
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

    {:ok, client} = :cqerl.get_client()

    ref =
      :cqerl.send_query(
        client,
        cql_query(
          statement:
            "SELECT #{CQL.list_to_cql(fields)} FROM archethic.transactions WHERE address=?",
          values: [address: address]
        )
      )

    receive do
      {:result, ^ref, result} ->
        case :cqerl.head(result) do
          :empty_dataset ->
            {:error, :transaction_not_exists}

          tx ->
            :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
              query: "get_transaction"
            })

            {:ok, format_result_to_transaction(tx)}
        end
    after
      5_000 ->
        raise "Timeout on get_transaction"
    end
  end

  @impl DB
  @doc """
  Fetch the transaction chain by address and project the requested fields from the transactions
  """
  @spec get_transaction_chain(binary(), list()) :: Enumerable.t()
  def get_transaction_chain(address, fields \\ []) when is_binary(address) and is_list(fields) do
    start = System.monotonic_time()

    1..4
    |> Task.async_stream(fn bucket ->
      {:ok, client} = :cqerl.get_client()
      {bucket, stream_transaction_chain(client, address, bucket, fields)}
    end)
    |> Stream.transform(0, fn {:ok, {bucket, stream}}, acc ->
      if acc == 4 do
        :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
          query: "get_transaction_chain"
        })

        {:halt, acc}
      else
        {Enum.to_list(stream), bucket}
      end
    end)
  end

  defp stream_transaction_chain(client, address, bucket, fields) do
    Stream.resource(
      fn ->
        :cqerl.send_query(
          client,
          cql_query(
            statement:
              "SELECT #{CQL.list_to_cql(fields)} FROM archethic.transactions WHERE chain_address=? and bucket=?",
            values: [chain_address: address, bucket: bucket]
          )
        )
      end,
      fn
        :eof ->
          {:halt, :eof}

        ref ->
          receive do
            {:result, ^ref, result} ->
              rows = :cqerl.all_rows(result)

              case :cqerl.fetch_more_async(result) do
                :no_more_result ->
                  {rows, :eof}

                ref ->
                  {rows, ref}
              end
          end
      end,
      fn _ -> :ok end
    )
    |> Stream.map(&format_result_to_transaction/1)
  end

  @impl DB
  @doc """
  Store the transaction
  """
  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(tx = %Transaction{address: address}) do
    {:ok, client} = :cqerl.get_client()
    do_write_transaction(client, tx, address)
  end

  @impl DB
  @doc """
  Store the transaction into the given chain address
  """
  @spec write_transaction(Transaction.t(), binary()) :: :ok
  def write_transaction(tx = %Transaction{}, chain_address) when is_binary(chain_address) do
    {:ok, client} = :cqerl.get_client()
    do_write_transaction(client, tx, chain_address)
  end

  defp do_write_transaction(
         client,
         tx = %Transaction{},
         chain_address
       ) do
    start = System.monotonic_time()

    batch_query = cql_query_batch(queries: write_transaction_batch_queries(tx, chain_address))
    {:ok, :void} = :cqerl.run_query(client, batch_query)

    :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
      query: "write_transaction"
    })

    :ok
  end

  defp write_transaction_batch_queries(tx, chain_address) do
    [
      cql_query(
        statement:
          "INSERT INTO archethic.transactions (chain_address, bucket, timestamp, version, address, type, data, previous_public_key, previous_signature, origin_signature, validation_stamp, cross_validation_stamps) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        values: encode_transaction_to_parameters(tx, chain_address)
      ),
      cql_query(
        statement:
          "INSERT INTO archethic.transaction_type_lookup(type, address, timestamp) VALUES(?, ?, ?)",
        values: [
          type: tx.type,
          address: tx.address,
          timestamp: DateTime.to_unix(tx.validation_stamp.timestamp, :millisecond)
        ]
      )
    ]
  end

  defp encode_transaction_to_parameters(
         tx = %Transaction{validation_stamp: %ValidationStamp{timestamp: timestamp}},
         chain_address
       ) do
    tx
    |> Transaction.to_map()
    |> update_in([:validation_stamp, :timestamp], &DateTime.to_unix(&1, :millisecond))
    |> Map.put(:timestamp, DateTime.to_unix(timestamp, :millisecond))
    |> Map.put(:chain_address, chain_address)
    |> Map.put(:bucket, bucket_from_date(timestamp))
    |> deep_map_to_list()
  end

  defp deep_map_to_list(map) when is_map(map) do
    Enum.reduce(map, [], fn
      {k, v}, acc when is_struct(v) ->
        [{k, v} | acc]

      {k, v}, acc when is_map(v) ->
        [{k, deep_map_to_list(v)} | acc]

      {k, v}, acc when is_list(v) ->
        [{k, Enum.map(v, &deep_map_to_list/1)} | acc]

      {k, v}, acc ->
        [{k, v} | acc]
    end)
  end

  defp deep_map_to_list(other), do: other

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

    {:ok, client} = :cqerl.get_client()

    statement_by_first_address =
      "INSERT INTO archethic.chain_lookup_by_first_address(last_transaction_address, genesis_transaction_address) VALUES (?, ?)"

    statement_by_first_key =
      "INSERT INTO archethic.chain_lookup_by_first_key(last_key, genesis_key) VALUES (?, ?)"

    statement_by_last_address =
      "INSERT INTO archethic.chain_lookup_by_last_address(transaction_address, last_transaction_address, timestamp) VALUES(?, ?, ?)"

    chain
    |> Stream.map(fn tx ->
      queries =
        write_transaction_batch_queries(tx, chain_address) ++
          [
            cql_query(
              statement: statement_by_first_address,
              values: [
                last_transaction_address: chain_address,
                genesis_transaction_address: tx.address
              ]
            ),
            cql_query(
              statement: statement_by_first_key,
              values: [last_key: chain_public_key, genesis_key: tx.previous_public_key]
            ),
            cql_query(
              statement: statement_by_last_address,
              values: [
                transaction_address: tx.address,
                last_transaction_address: chain_address,
                timestamp: DateTime.to_unix(tx.validation_stamp.timestamp, :millisecond)
              ]
            ),
            cql_query(
              statement: statement_by_last_address,
              values: [
                transaction_address: Transaction.previous_address(tx),
                last_transaction_address: chain_address,
                timestamp: DateTime.to_unix(tx.validation_stamp.timestamp, :millisecond)
              ]
            )
          ]

      {:ok, :void} = :cqerl.run_query(client, cql_query_batch(queries: queries))
    end)
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
    |> list_to_map()
    |> format_timestamp()
    |> Transaction.from_map()
  end

  defp format_timestamp(keyword) do
    case get_in(keyword, [Access.key(:validation_stamp, %{}), :timestamp]) do
      nil ->
        keyword

      timestamp ->
        Map.update!(
          keyword,
          :validation_stamp,
          &Map.put(&1, :timestamp, DateTime.from_unix!(timestamp, :millisecond))
        )
    end
  end

  def list_to_map(keyord_list = [{_, _} | _]) do
    Enum.reduce(keyord_list, %{}, fn
      {k, v}, acc when is_list(v) ->
        if Keyword.keyword?(v) do
          normalize_list_key(k, list_to_map(v), acc)
        else
          normalize_list_key(k, list_to_map(v), acc)
        end

      {k, v}, acc ->
        normalize_list_key(k, list_to_map(v), acc)
    end)
  end

  def list_to_map(list) when is_list(list) do
    Enum.map(list, &list_to_map/1)
  end

  def list_to_map({k, v}), do: normalize_list_key(k, list_to_map(v), %{})

  def list_to_map(:null), do: nil
  def list_to_map(other), do: other

  defp normalize_list_key(k, v, acc) when is_binary(k), do: Map.put(acc, k, v)

  defp normalize_list_key(k, v, acc) do
    case k |> Atom.to_string() |> String.split(".") do
      [] ->
        Map.put(acc, k, v)

      path ->
        put_in(acc, nested_path(path), v)
    end
  end

  defp nested_path(_keys, acc \\ [])

  defp nested_path([key | []], acc) do
    Enum.reverse([Access.key(String.to_existing_atom(key)) | acc])
  end

  defp nested_path([key | rest], acc) do
    nested_path(rest, [Access.key(String.to_existing_atom(key), %{}) | acc])
  end

  @doc """
  Reference a last address from a previous address
  """
  @impl DB
  @spec add_last_transaction_address(binary(), binary(), DateTime.t()) :: :ok
  def add_last_transaction_address(tx_address, last_address, timestamp = %DateTime{}) do
    {:ok, client} = :cqerl.get_client()

    statement =
      "INSERT INTO archethic.chain_lookup_by_last_address(transaction_address, last_transaction_address, timestamp) VALUES(?, ?, ?)"

    {:ok, _} =
      :cqerl.run_query(
        client,
        cql_query(
          statement: statement,
          values: [
            transaction_address: tx_address,
            last_transaction_address: last_address,
            timestamp: DateTime.to_unix(timestamp, :millisecond)
          ]
        )
      )

    :ok
  end

  @doc """
  List the last transaction lookups
  """
  @impl DB
  @spec list_last_transaction_addresses() :: Enumerable.t()
  def list_last_transaction_addresses do
    {:ok, client} = :cqerl.get_client()

    statement = "SELECT * FROM archethic.chain_lookup_by_last_address PER PARTITION LIMIT 1"

    Stream.resource(
      fn ->
        {:ok, result} = :cqerl.run_query(client, statement)
        result
      end,
      fn result ->
        case :cqerl.next(result) do
          :empty_dataset ->
            {:halt, []}

          {head, tail} ->
            transaction_address = Keyword.get(head, :transaction_address)
            last_address = Keyword.get(head, :last_transaction_address)
            timestamp = Keyword.get(head, :timestamp)

            {[{transaction_address, last_address, DateTime.from_unix!(timestamp, :millisecond)}],
             tail}
        end
      end,
      fn _ -> :ok end
    )
  end

  @impl DB
  @spec chain_size(binary()) :: non_neg_integer()
  def chain_size(address) do
    {:ok, client} = :cqerl.get_client()

    ref =
      :cqerl.send_query(
        client,
        cql_query(
          statement:
            "SELECT COUNT(address) as size FROM archethic.transactions WHERE chain_address=?",
          values: [chain_address: address]
        )
      )

    receive do
      {:result, ^ref, result} ->
        case :cqerl.head(result) do
          :empty_dataset ->
            0

          [size: size] ->
            size
        end
    after
      5_000 ->
        raise "Timeout for chain_size request"
    end
  end

  @impl DB
  @spec list_transactions_by_type(type :: Transaction.transaction_type(), fields :: list()) ::
          Enumerable.t()
  def list_transactions_by_type(type, fields \\ []) do
    {:ok, client} = :cqerl.get_client()

    Stream.resource(
      fn ->
        :cqerl.send_query(
          client,
          cql_query(
            statement: "SELECT address FROM archethic.transaction_type_lookup WHERE type=?",
            values: [type: type]
          )
        )
      end,
      fn
        :eof ->
          {:halt, :eof}

        ref ->
          receive do
            {:result, ^ref, result} ->
              rows =
                result
                |> :cqerl.all_rows()
                |> Stream.map(&Keyword.get(&1, :address))
                |> Stream.map(fn address ->
                  {:ok, tx} = get_transaction(address, fields)
                  tx
                end)

              case :cqerl.fetch_more_async(result) do
                :no_more_result ->
                  {rows, :eof}

                ref ->
                  {rows, ref}
              end
          after
            5_000 ->
              raise "Timeout on list_transactions"
          end
      end,
      fn _ -> :ok end
    )
  end

  @impl DB
  @spec count_transactions_by_type(type :: Transaction.transaction_type()) :: non_neg_integer()
  def count_transactions_by_type(type) do
    {:ok, client} = :cqerl.get_client()

    ref =
      :cqerl.send_query(
        client,
        cql_query(
          statement:
            "SELECT COUNT(address) as size FROM archethic.transaction_type_lookup WHERE type=?",
          values: [type: Atom.to_string(type)]
        )
      )

    receive do
      {:result, ^ref, result} ->
        case :cqerl.head(result) do
          :empty_dataset ->
            0

          [size: size] ->
            size
        end
    after
      5_000 ->
        raise "Timeout for chain_size request"
    end
  end

  @doc """
  Get the last transaction address of a chain
  """
  @impl DB
  @spec get_last_chain_address(binary()) :: binary()
  def get_last_chain_address(address) do
    {:ok, client} = :cqerl.get_client()

    :cqerl.send_query(
      client,
      cql_query(
        statement:
          "SELECT last_transaction_address FROM archethic.chain_lookup_by_last_address WHERE transaction_address = ?",
        values: [transaction_address: address]
      )
    )

    receive do
      {:result, _, result} ->
        case :cqerl.head(result) do
          :empty_dataset ->
            address

          [last_transaction_address: last_transaction_address] ->
            last_transaction_address
        end
    after
      5_000 ->
        raise "Timout get_last_chain_address"
    end
  end

  @doc """
  Get the last transaction address of a chain before a given certain datetime
  """
  @impl DB
  @spec get_last_chain_address(binary(), DateTime.t()) :: binary()
  def get_last_chain_address(address, datetime = %DateTime{}) do
    {:ok, client} = :cqerl.get_client()

    ref =
      :cqerl.send_query(
        client,
        cql_query(
          statement:
            "SELECT last_transaction_address FROM archethic.chain_lookup_by_last_address WHERE transaction_address = ? and timestamp <= ?",
          values: [
            transaction_address: address,
            timestamp: DateTime.to_unix(datetime, :millisecond)
          ]
        )
      )

    receive do
      {:result, ^ref, result} ->
        case :cqerl.head(result) do
          :empty_dataset ->
            address

          [last_transaction_address: last_transaction_address] ->
            last_transaction_address
        end
    after
      5_000 ->
        raise "Timout get_last_chain_address"
    end
  end

  @doc """
  Get the first transaction address for a chain
  """
  @impl DB
  @spec get_first_chain_address(binary()) :: binary()
  def get_first_chain_address(address) when is_binary(address) do
    {:ok, client} = :cqerl.get_client()

    :cqerl.send_query(
      client,
      cql_query(
        statement:
          "SELECT genesis_transaction_address FROM archethic.chain_lookup_by_first_address WHERE last_transaction_address = ?",
        values: [last_transaction_address: address]
      )
    )

    receive do
      {:result, _, result} ->
        case :cqerl.head(result) do
          :empty_dataset ->
            address

          [genesis_transaction_address: genesis_transaction_address] ->
            genesis_transaction_address
        end
    after
      5_000 ->
        raise "Timout get_first_chain_address"
    end
  end

  @doc """
  Get the first public key of of transaction chain
  """
  @impl DB
  @spec get_first_public_key(Crypto.key()) :: Crypto.key()
  def get_first_public_key(previous_public_key) when is_binary(previous_public_key) do
    {:ok, client} = :cqerl.get_client()

    :cqerl.send_query(
      client,
      cql_query(
        statement:
          "SELECT genesis_key FROM archethic.chain_lookup_by_first_key WHERE last_key = ?",
        values: [last_key: previous_public_key]
      )
    )

    receive do
      {:result, _, result} ->
        case :cqerl.head(result) do
          :empty_dataset ->
            previous_public_key

          [genesis_key: genesis_key] ->
            genesis_key
        end
    after
      5_000 ->
        raise "Timout get_first_public_key"
    end
  end

  @doc """
  Return the latest TPS record
  """
  @impl DB
  @spec get_latest_tps :: float()
  def get_latest_tps do
    {:ok, client} = :cqerl.get_client()
    {:ok, result} = :cqerl.run_query(client, "SELECT tps FROM archethic.network_stats_by_date")

    case :cqerl.head(result) do
      :empty_dataset ->
        0.0

      [tps: tps] ->
        tps
    end
  end

  @doc """
  Returns the number of transactions
  """
  @impl DB
  @spec get_nb_transactions() :: non_neg_integer()
  def get_nb_transactions do
    {:ok, client} = :cqerl.get_client()

    {:ok, result} =
      :cqerl.run_query(client, "SELECT nb_transactions FROM archethic.network_stats_by_date")

    result
    |> :cqerl.all_rows()
    |> Enum.map(&Keyword.get(&1, :nb_transactions))
    |> Enum.reduce(0, fn nb_transactions, acc -> nb_transactions + acc end)
  end

  @doc """
  Register a new TPS for the given date
  """
  @impl DB
  @spec register_tps(DateTime.t(), float(), non_neg_integer()) :: :ok
  def register_tps(date = %DateTime{}, tps, nb_transactions)
      when is_float(tps) and tps >= 0.0 and is_integer(nb_transactions) and nb_transactions >= 0 do
    {:ok, client} = :cqerl.get_client()

    {:ok, _} =
      :cqerl.run_query(
        client,
        cql_query(
          statement:
            "INSERT INTO archethic.network_stats_by_date (date, tps, nb_transactions) VALUES (?, ?, ?)",
          values: [
            date: DateTime.to_unix(date, :millisecond),
            tps: tps,
            nb_transactions: nb_transactions
          ]
        )
      )

    :ok
  end

  @doc """
  Determines if the transaction address exists
  """
  @impl DB
  @spec transaction_exists?(binary()) :: boolean()
  def transaction_exists?(address) when is_binary(address) do
    {:ok, client} = :cqerl.get_client()

    {:ok, result} =
      :cqerl.run_query(
        client,
        cql_query(
          statement: "SELECT COUNT(address) as count FROM archethic.transactions WHERE address=?",
          values: [address: address]
        )
      )

    case :cqerl.head(result) do
      [count: count] when count > 0 ->
        true

      _ ->
        false
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
          average_availability :: non_neg_integer()
        ) :: :ok
  def register_p2p_summary(
        node_public_key,
        date = %DateTime{},
        available?,
        avg_availability
      ) do
    {:ok, client} = :cqerl.get_client()

    {:ok, _} =
      :cqerl.run_query(
        client,
        cql_query(
          statement:
            "INSERT INTO archethic.p2p_summary_by_node (node_public_key, date, available, average_availability) VALUES (?, ?, ?, ?)",
          values: [
            node_public_key: node_public_key,
            date: DateTime.to_unix(date, :millisecond),
            available: available?,
            average_availability: avg_availability
          ]
        )
      )

    :ok
  end

  @doc """
  Get the last p2p summaries
  """
  @impl DB
  @spec get_last_p2p_summaries() :: Enumerable.t()
  def get_last_p2p_summaries do
    Stream.resource(
      fn ->
        {:ok, client} = :cqerl.get_client()

        :cqerl.send_query(
          client,
          "SELECT node_public_key, available, average_availability FROM archethic.p2p_summary_by_node PER PARTITION LIMIT 1"
        )
      end,
      fn
        :eof ->
          {:halt, :eof}

        ref ->
          receive do
            {:result, ^ref, result} ->
              rows = :cqerl.all_rows(result)

              case :cqerl.fetch_more_async(result) do
                :no_more_result ->
                  {rows, :eof}

                ref ->
                  {rows, ref}
              end
          end
      end,
      fn _ -> :ok end
    )
    |> Stream.map(fn [
                       node_public_key: node_public_key,
                       available: available?,
                       average_availability: avg_availability
                     ] ->
      {node_public_key, {available?, avg_availability}}
    end)
  end
end
