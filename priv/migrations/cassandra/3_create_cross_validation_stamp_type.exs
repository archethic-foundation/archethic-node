defmodule Uniris.DB.CassandraImpl.Migrations.CreateCrossValidationStampType do
  def execute do
    Xandra.execute!(:xandra_conn, """
    CREATE TYPE IF NOT EXISTS uniris.cross_validation_stamp(
      node_public_key blob,
      signature blob
    );
    """)
  end
end
