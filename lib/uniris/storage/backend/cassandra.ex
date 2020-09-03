defmodule Uniris.Storage.CassandraBackend do
  @moduledoc false

  @insert_transaction_stmt """
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

  @insert_transaction_chain_stmt """
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

  @insert_node_transaction_stmt """
  INSERT INTO uniris.node_transactions(address, bucket, timestamp)
  VALUES(?, ?, ?)
  """

  alias __MODULE__.CQL
  alias __MODULE__.SchemaMigrator

  alias Uniris.Transaction
  alias Uniris.Utils

  @behaviour Uniris.Storage.BackendImpl

  @impl true
  def child_spec(arg) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [arg]}, restart: :permanent}
  end

  def start_link(_) do
    nodes =
      :uniris
      |> Application.get_env(__MODULE__, nodes: ["127.0.0.1:9042"])
      |> Keyword.fetch!(:nodes)

    {:ok, pid} =
      Xandra.start_link(
        name: :xandra_conn,
        pool_size: 10,
        nodes: nodes
      )

    SchemaMigrator.run()
    {:ok, pid}
  end

  @impl true
  def migrate do
    SchemaMigrator.run()
  end

  @impl true
  def list_transactions(fields \\ []) do
    Xandra.stream_pages!(
      :xandra_conn,
      "SELECT #{CQL.list_to_cql(fields)} FROM uniris.transactions",
      _params = []
    )
    |> Stream.flat_map(& &1)
    |> Stream.map(&format_result_to_transaction/1)
  end

  @impl true
  def list_transaction_chains_info do
    Xandra.stream_pages!(
      :xandra_conn,
      """
      SELECT size, chain_address as address, fork
      FROM uniris.transaction_chains
      """,
      _params = []
    )
    |> Stream.flat_map(& &1)
    |> Stream.filter(fn %{"fork" => fork} -> fork == System.get_env("UNIRIS_DB_FORK", "main") end)
    |> Stream.map(fn %{"address" => address, "size" => size} ->
      {address, size}
    end)
  end

  @impl true
  def get_transaction(address, fields \\ []) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT #{CQL.list_to_cql(fields)} FROM uniris.transactions WHERE address=?"
      )

    Xandra.execute!(:xandra_conn, prepared, [address])
    |> Enum.to_list()
    |> case do
      [] ->
        {:error, :transaction_not_exists}

      [tx] ->
        {:ok, format_result_to_transaction(tx)}
    end
  end

  @impl true
  def get_transaction_chain(address, fields \\ []) do
    prepared =
      Xandra.prepare!(:xandra_conn, """
        SELECT transaction_address
        FROM uniris.transaction_chains
        WHERE chain_address=? and fork=?
      """)

    Xandra.stream_pages!(:xandra_conn, prepared, %{"chain_address" => address, "fork" => "main"})
    |> Stream.flat_map(& &1)
    |> Stream.map(fn %{"transaction_address" => address} ->
      {:ok, tx} = get_transaction(address, fields)
      tx
    end)
  end

  @impl true
  @spec list_transactions_by_type(type :: Transaction.type(), fields :: list()) ::
          Enumerable.t()
  def list_transactions_by_type(type, fields \\ []) do
    prepared =
      Xandra.prepare!(:xandra_conn, """
      SELECT #{CQL.list_to_cql(fields)}
      FROM uniris.transactions
      WHERE type = ?
      """)

    Xandra.stream_pages!(:xandra_conn, prepared, %{"type" => Atom.to_string(type)})
    |> Stream.flat_map(& &1)
    |> Stream.map(&format_result_to_transaction/1)
  end

  @impl true
  def write_transaction(tx = %Transaction{type: type, timestamp: timestamp, address: address}) do
    prepared = Xandra.prepare!(:xandra_conn, @insert_transaction_stmt)
    {:ok, _} = Xandra.execute(:xandra_conn, prepared, transaction_write_parameters(tx))

    case type do
      :node ->
        prepared = Xandra.prepare!(:xandra_conn, @insert_node_transaction_stmt)

        {:ok, _} =
          Xandra.execute(:xandra_conn, prepared, %{
            "address" => address,
            "timestamp" => timestamp,
            "bucket" => timestamp.month
          })

        :ok

      _ ->
        :ok
    end
  end

  @impl true
  def write_transaction_chain(chain = [%Transaction{address: chain_address} | _]) do
    transaction_prepared = Xandra.prepare!(:xandra_conn, @insert_transaction_stmt)
    chain_prepared = Xandra.prepare!(:xandra_conn, @insert_transaction_chain_stmt)

    chain_size = length(chain)

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
    |> Map.update!("type", &to_string(&1))
  end

  defp transaction_chain_write_parameters(chain_address, tx = %Transaction{}, chain_size) do
    %{
      "chain_address" => chain_address,
      "transaction_address" => tx.address,
      "size" => chain_size,
      "timestamp" => tx.timestamp,
      "fork" => "main"
    }
  end

  def format_result_to_transaction(res) do
    res
    |> Utils.atomize_keys()
    |> Map.update!(:type, &String.to_atom(&1))
    |> Transaction.from_map()
  end
end
