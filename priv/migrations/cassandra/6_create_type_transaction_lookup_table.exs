defmodule Uniris.DB.CassandraImpl.Migrations.CreateTypeTransactionLookupTable do
  def execute do
    Xandra.execute!(:xandra_conn, """
    CREATE TABLE uniris.transaction_type_lookup(
      type varchar,
      address blob,
      timestamp timestamp,
      PRIMARY KEY (type, timestamp)
    ) WITH CLUSTERING ORDER BY (timestamp DESC);
    """)
  end
end
