defmodule Uniris.DB.CassandraImpl.SchemaMigrator do
  @moduledoc false

  require Logger

  @doc """
  Run the migrations
  """
  @spec run() :: :ok
  def run do
    create_keyspace()
    create_transaction_data_user_type()
    create_validation_stamp_user_type()
    create_cross_validation_stamp_user_type()
    create_transaction_table()
    create_transaction_chain_table()
    create_chain_lookup_table()
    create_beacon_chain_types()
    create_beacon_chain_slot_table()
    create_beacon_chain_summary_table()

    Logger.info("Schema database initialized")
  end

  defp create_keyspace do
    Logger.info("keyspace creation...")

    Xandra.execute!(:xandra_conn, """
    CREATE KEYSPACE IF NOT EXISTS uniris WITH replication = {
      'class': 'SimpleStrategy',
      'replication_factor' : 1
    };
    """)
  end

  defp create_transaction_table do
    Logger.info("transaction table creation...")

    Xandra.execute!(:xandra_conn, """
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

    create_transaction_data_ledger_type()
    create_transaction_data_keys_type()

    Xandra.execute!(:xandra_conn, """
    CREATE TYPE IF NOT EXISTS uniris.pending_transaction_data(
      code text,
      content text,
      recipients LIST<blob>,
      ledger frozen<pending_transaction_ledger>,
      keys frozen<pending_transaction_data_keys>
    );
    """)
  end

  defp create_transaction_data_ledger_type do
    create_transaction_data_uco_ledger_type()
    create_transaction_data_nft_ledger_type()

    Xandra.execute!(:xandra_conn, """
    CREATE TYPE IF NOT EXISTS uniris.pending_transaction_ledger(
      uco frozen<uco_ledger>,
      nft frozen<nft_ledger>
    );
    """)
  end

  defp create_transaction_data_uco_ledger_type do
    Xandra.execute!(:xandra_conn, """
    CREATE TYPE IF NOT EXISTS uniris.uco_transfer(
      "to" blob,
      amount double
    );
    """)

    Xandra.execute!(:xandra_conn, """
    CREATE TYPE IF NOT EXISTS uniris.uco_ledger(
      transfers LIST<frozen<uco_transfer>>
    );
    """)
  end

  defp create_transaction_data_nft_ledger_type do
    Xandra.execute!(:xandra_conn, """
    CREATE TYPE IF NOT EXISTS uniris.nft_transfer(
      "to" blob,
      amount double,
      nft blob
    );
    """)

    Xandra.execute!(:xandra_conn, """
    CREATE TYPE IF NOT EXISTS uniris.nft_ledger(
      transfers LIST<frozen<nft_transfer>>
    );
    """)
  end

  defp create_transaction_data_keys_type do
    Xandra.execute!(:xandra_conn, """
    CREATE TYPE IF NOT EXISTS uniris.pending_transaction_data_keys(
      authorized_keys map<blob, blob>,
      secret blob
    );
    """)
  end

  defp create_validation_stamp_user_type do
    Logger.info("validation_stamp user type creation...")

    create_ledger_operations_transaction_movement_type()
    create_ledger_operations_node_movement_type()
    create_ledger_operations_unspent_output_type()
    create_ledger_operations_type()

    Xandra.execute!(:xandra_conn, """
    CREATE TYPE IF NOT EXISTS uniris.validation_stamp(
      proof_of_work blob,
      proof_of_integrity blob,
      ledger_operations frozen<ledger_operations>,
      signature blob
    );
    """)
  end

  defp create_ledger_operations_node_movement_type do
    Xandra.execute!(:xandra_conn, """
    CREATE TYPE IF NOT EXISTS uniris.ledger_operations_node_movement(
      "to" blob,
      amount double,
      roles list<text>
    );
    """)
  end

  defp create_ledger_operations_transaction_movement_type do
    Xandra.execute!(:xandra_conn, """
    CREATE TYPE IF NOT EXISTS uniris.ledger_operations_transaction_movement(
      "to" blob,
      amount double,
      type varchar,
      nft_address blob
    );
    """)
  end

  defp create_ledger_operations_unspent_output_type do
    Xandra.execute!(:xandra_conn, """
    CREATE TYPE IF NOT EXISTS uniris.ledger_operations_unspent_output(
      "from" blob,
      amount double,
      type varchar,
      nft_address blob
    );
    """)
  end

  defp create_ledger_operations_type do
    Xandra.execute!(:xandra_conn, """
    CREATE TYPE IF NOT EXISTS uniris.ledger_operations(
      fee float,
      transaction_movements LIST<frozen<ledger_operations_transaction_movement>>,
      node_movements LIST<frozen<ledger_operations_node_movement>>,
      unspent_outputs LIST<frozen<ledger_operations_unspent_output>>
    );
    """)
  end

  defp create_cross_validation_stamp_user_type do
    Logger.info("cross_validation_stamp user type creation...")

    Xandra.execute!(:xandra_conn, """
    CREATE TYPE IF NOT EXISTS uniris.cross_validation_stamp(
      node_public_key blob,
      signature blob
    );
    """)
  end

  defp create_transaction_chain_table do
    Logger.info("transaction_chains table creation...")

    Xandra.execute!(:xandra_conn, """
    CREATE TABLE IF NOT EXISTS uniris.transaction_chains(
      chain_address blob,
      size int,
      transaction_address blob,
      timestamp timestamp,
      PRIMARY KEY (chain_address, timestamp)
    )
    WITH CLUSTERING ORDER BY (timestamp DESC);
    """)
  end

  defp create_chain_lookup_table do
    Logger.info("chain_lookup table creation...")

    Xandra.execute!(:xandra_conn, """
    CREATE TABLE IF NOT EXISTS uniris.chain_lookup(
      transaction_address blob,
      last_transaction_address blob,
      PRIMARY KEY (transaction_address)
    )
    """)
  end

  defp create_beacon_chain_types do
    Xandra.execute!(:xandra_conn, """
    CREATE TYPE IF NOT EXISTS uniris.beacon_chain_transaction_summary(
      address blob,
      type varchar,
      timestamp timestamp,
      movements_addresses LIST<blob>
    );
    """)

    Xandra.execute!(:xandra_conn, """
    CREATE TYPE IF NOT EXISTS uniris.beacon_chain_end_of_node_sync(
      node_public_key blob,
      timestamp timestamp
    );
    """)
  end

  defp create_beacon_chain_slot_table do
    Logger.info("beacon_chain_slot table creation...")

    Xandra.execute!(:xandra_conn, """
    CREATE TABLE IF NOT EXISTS uniris.beacon_chain_slot(
      subset blob,
      slot_time timestamp,
      previous_hash blob,
      transaction_summaries LIST<frozen<beacon_chain_transaction_summary>>,
      end_of_node_synchronizations LIST<frozen<beacon_chain_end_of_node_sync>>,
      p2p_view LIST<boolean>,
      involved_nodes LIST<boolean>,
      validation_signatures LIST<frozen<tuple<int, blob>>>,
      PRIMARY KEY (subset, slot_time)
    )
    WITH CLUSTERING ORDER BY (slot_time DESC) AND default_time_to_live = 1200;
    """)
  end

  defp create_beacon_chain_summary_table do
    Logger.info("beacon_chain_summary table creation...")

    Xandra.execute!(:xandra_conn, """
    CREATE TABLE IF NOT EXISTS uniris.beacon_chain_summary(
      subset blob,
      summary_time timestamp,
      transaction_summaries LIST<frozen<beacon_chain_transaction_summary>>,
      end_of_node_synchronizations LIST<frozen<beacon_chain_end_of_node_sync>>,
      PRIMARY KEY (subset, summary_time)
    )
    WITH CLUSTERING ORDER BY (summary_time DESC);
    """)
  end
end
