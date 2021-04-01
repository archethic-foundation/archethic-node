defmodule Uniris.DB.CassandraImpl.Migrations.CreateBeaconSlotTable do
  def execute do
    Xandra.execute!(:xandra_conn, """
    CREATE TABLE IF NOT EXISTS uniris.beacon_chain_slot(
      subset blob,
      slot_time timestamp,
      previous_hash blob,
      transaction_summaries LIST<frozen<beacon_chain_transaction_summary>>,
      end_of_node_synchronizations LIST<frozen<beacon_chain_end_of_node_sync>>,
      p2p_view LIST<boolean>,
      involved_nodes LIST<boolean>,
      validation_signatures map<int, blob>,
      PRIMARY KEY (subset, slot_time)
    )
    WITH CLUSTERING ORDER BY (slot_time DESC) AND default_time_to_live = 1200;
    """)
  end
end
