defmodule Uniris.DB.CassandraImpl.Migrations.CreateTransactionDataTypes do
  def execute do
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
end
