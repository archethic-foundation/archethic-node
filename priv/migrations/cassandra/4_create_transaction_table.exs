defmodule Uniris.DB.CassandraImpl.Migrations.CreateTransactionTable do
  def execute do
    Xandra.execute!(:xandra_conn, """
    CREATE TABLE IF NOT EXISTS uniris.transactions (
      address blob,
      type varchar,
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
end
