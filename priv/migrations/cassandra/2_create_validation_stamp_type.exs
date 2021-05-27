defmodule Uniris.DB.CassandraImpl.Migrations.CreateValidationStampType do
  def execute do
    create_ledger_operations_transaction_movement_type()
    create_ledger_operations_node_movement_type()
    create_ledger_operations_unspent_output_type()
    create_ledger_operations_type()

    Xandra.execute!(:xandra_conn, """
    CREATE TYPE IF NOT EXISTS uniris.validation_stamp(
      timestamp timestamp,
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
      nft_address blob,
      reward boolean
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
end
