defmodule Uniris.DB.CassandraImpl.Migrations.CreateBeaconSummaryTable do
  def execute do
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
