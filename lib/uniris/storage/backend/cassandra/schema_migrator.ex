defmodule Uniris.Storage.CassandraBackend.SchemaMigrator do
  @moduledoc false
  require Logger

  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    run()
    {:ok, []}
  end

  def run do
    with {:ok, _} <- create_keyspace(),
         {:ok, _} <- create_transaction_data_user_type(),
         {:ok, _} <- create_validation_stamp_user_type(),
         {:ok, _} <- create_cross_validation_stamp_user_type(),
         {:ok, _} <- create_transaction_table(),
         {:ok, _} <- create_transaction_chain_table() do
      Logger.info("Schema database initialized")
    end
  end

  defp create_keyspace do
    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE KEYSPACE IF NOT EXISTS uniris WITH replication = {
        'class': 'SimpleStrategy',
        'replication_factor' : 1
      };
      """)
  end

  defp create_transaction_table do
    Xandra.execute(:xandra_conn, """
    CREATE TABLE IF NOT EXISTS uniris.transactions (
      address varchar,
      type varchar,
      timestamp timestamp,
      data frozen<pending_transaction_data>,
      previous_public_key varchar,
      previous_signature varchar,
      origin_signature varchar,
      validation_stamp frozen<validation_stamp>,
      cross_validation_stamps LIST<frozen<cross_validation_stamp>>,
      PRIMARY KEY (address)
    );
    """)
  end

  defp create_transaction_data_user_type do
    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TYPE IF NOT EXISTS uniris.transfer(
        recipient varchar,
        amount float
      );
      """)

    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TYPE IF NOT EXISTS uniris.uco_ledger(
        transfers LIST<frozen<transfer>>
      );
      """)

    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TYPE IF NOT EXISTS uniris.pending_transaction_ledger(
        uco frozen<uco_ledger>
      );
      """)

    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TYPE IF NOT EXISTS uniris.pending_transaction_data_keys(
        authorized_keys map<varchar, varchar>,
        secret varchar
      )
      """)

    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TYPE IF NOT EXISTS uniris.pending_transaction_data(
        code text,
        content text,
        recipients LIST<varchar>,
        ledger frozen<pending_transaction_ledger>,
        keys frozen<pending_transaction_data_keys>
      );
      """)
  end

  defp create_validation_stamp_user_type do
    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TYPE IF NOT EXISTS uniris.ledger_operations_movement(
        recipient varchar,
        amount float
      );
      """)

    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TYPE IF NOT EXISTS uniris.ledger_operations_utxo(
        origin varchar,
        amount float
      )
      """)

    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TYPE IF NOT EXISTS uniris.ledger_operations(
        fee float,
        transaction_movements LIST<frozen<ledger_operations_movement>>,
        node_movements LIST<frozen<ledger_operations_movement>>,
        unspent_outputs LIST<frozen<ledger_operations_utxo>>
      );
      """)

    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TYPE IF NOT EXISTS uniris.validation_stamp(
        proof_of_work varchar,
        proof_of_integrity varchar,
        ledger_operations frozen<ledger_operations>,
        signature varchar
      );
      """)
  end

  defp create_cross_validation_stamp_user_type do
    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TYPE IF NOT EXISTS uniris.cross_validation_stamp(
        node varchar,
        signature varchar
      )
      """)
  end

  defp create_transaction_chain_table do
    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TABLE IF NOT EXISTS uniris.transaction_chains(
        chain_address varchar,
        fork varchar,
        size int,
        transaction_address varchar,
        timestamp timestamp,
        PRIMARY KEY ((chain_address, fork), timestamp)
      )
      WITH CLUSTERING ORDER BY (timestamp DESC);
      """)
  end
end
