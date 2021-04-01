defmodule Uniris.DB.CassandraImpl.Migrations.CreateChainLookupByFirstKeyTable do
  def execute do
    Xandra.execute!(:xandra_conn, """
    CREATE TABLE IF NOT EXISTS uniris.chain_lookup_by_first_key(
      last_key blob,
      genesis_key blob,
      PRIMARY KEY (last_key)
    );
    """)
  end
end
