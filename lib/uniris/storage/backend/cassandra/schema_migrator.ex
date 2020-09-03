defmodule Uniris.Storage.CassandraBackend.SchemaMigrator do
  @moduledoc false
  require Logger

  def run do
    with {:ok, _} <- create_keyspace(),
         {:ok, _} <- create_transaction_data_user_type(),
         {:ok, _} <- create_validation_stamp_user_type(),
         {:ok, _} <- create_cross_validation_stamp_user_type(),
         {:ok, _} <- create_transaction_table(),
         {:ok, _} <- create_transaction_chain_table(),
         {:ok, _} <- create_transaction_type_index() do
      Logger.info("Schema database initialized")
    end
  end

  defp create_keyspace do
    Logger.info("keyspace creation...")

    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE KEYSPACE IF NOT EXISTS uniris WITH replication = {
        'class': 'SimpleStrategy',
        'replication_factor' : 1
      };
      """)
  end

  defp create_transaction_table do
    Logger.info("transaction table creation...")

    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TABLE IF NOT EXISTS uniris.transactions (
        address blob,
        type varchar,
        timestamp timestamp,
        data frozen<pending_transaction_data>,
        previous_public_key blob,
        previous_signature blob,
        origin_signature blob,
        validation_stamp frozen<validation_stamp>,
        cross_validation_stamps LIST<frozen<cross_validation_stamp>>,
        PRIMARY KEY (address)
      );
      """)
  end

  defp create_transaction_data_user_type do
    Logger.info("transaction_data user type creation...")

    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TYPE IF NOT EXISTS uniris.transfer(
        "to" blob,
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
        authorized_keys map<blob, blob>,
        secret blob
      );
      """)

    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TYPE IF NOT EXISTS uniris.pending_transaction_data(
        code text,
        content text,
        recipients LIST<blob>,
        ledger frozen<pending_transaction_ledger>,
        keys frozen<pending_transaction_data_keys>
      );
      """)
  end

  defp create_validation_stamp_user_type do
    Logger.info("validation_stamp user type creation...")

    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TYPE IF NOT EXISTS uniris.ledger_operations_movement(
        "to" blob,
        amount float
      );
      """)

    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TYPE IF NOT EXISTS uniris.ledger_operations_utxo(
        "from" blob,
        amount float
      );
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
        proof_of_work blob,
        proof_of_integrity blob,
        ledger_operations frozen<ledger_operations>,
        signature blob
      );
      """)
  end

  defp create_cross_validation_stamp_user_type do
    Logger.info("cross_validation_stamp user type creation...")

    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TYPE IF NOT EXISTS uniris.cross_validation_stamp(
        node_public_key blob,
        signature blob
      );
      """)
  end

  defp create_transaction_chain_table do
    Logger.info("transaction_chains table creation...")

    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TABLE IF NOT EXISTS uniris.transaction_chains(
        chain_address blob,
        fork varchar,
        size int,
        transaction_address blob,
        timestamp timestamp,
        PRIMARY KEY ((chain_address, fork), timestamp)
      )
      WITH CLUSTERING ORDER BY (timestamp DESC);
      """)
  end

  defp create_transaction_type_index do
    Logger.info("Transaction type index creation...")

    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE INDEX IF NOT EXISTS 
      ON uniris.transactions (type);
      """)
  end
end
