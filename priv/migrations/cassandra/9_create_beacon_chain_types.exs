defmodule Uniris.DB.CassandraImpl.Migrations.CreateBeaconChainTypes do
  def execute do
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
end
