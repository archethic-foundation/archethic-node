defmodule Uniris.DB.CassandraImpl.Migrations.CreateTransactionChainTable do
  def execute do
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
end
