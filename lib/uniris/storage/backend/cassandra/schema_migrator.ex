defmodule Uniris.Storage.CassandraBackend.SchemaMigrator do
  @moduledoc false
  require Logger

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    run_migrations()
    {:ok, []}
  end

  defp run_migrations do
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
    # Cassandra impose a query design scheme
    # And to avoid its limitation (< 2B cells and < 100MB per partition)
    # We need to split transaction chain by buckets

    # First attempt: using day number of the year we scan scale for a long running service
    # and with a lot of big transactions
    #
    # Examples:
    #   With a big transaction: 450 fields (200 validations, 10 transfers, 10 UTXO,
    #    1K contract, 1M content, 100K secrets) over 50 years with 1 transaction per minute
    #   We can reach 32M cells and 41MB per partition using this design
    #   NOTE: clients will need to perform 365 queries to retrived the entire chain
    #   NOTE: too much work on the clients

    ## 2nd attempt: To have good performance for reading from clients, using a mod 10 on timestamp of the transaction
    ## NOTE: Client will only need to perform 10 queries to lookup an entire transaction chain
    {:ok, _} =
      Xandra.execute(:xandra_conn, """
      CREATE TABLE IF NOT EXISTS uniris.transaction_chains(
        chain_address varchar,
        bucket int,
        size int,
        transaction_address varchar,
        type varchar,
        timestamp timestamp,
        data frozen<pending_transaction_data>,
        previous_public_key varchar,
        previous_signature varchar,
        origin_signature varchar,
        validation_stamp frozen<validation_stamp>,
        cross_validation_stamps LIST<frozen<cross_validation_stamp>>,
        PRIMARY KEY ((chain_address, bucket), timestamp)
      )
      WITH CLUSTERING ORDER BY (timestamp DESC);
      """)
  end
end
