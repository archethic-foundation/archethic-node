defmodule Uniris.DB.CassandraImpl.SchemaMigratorTest do
  use ExUnit.Case

  alias Uniris.DB.CassandraImpl.SchemaMigrator

  @tag infrastructure: true
  test "run/1 should create all the user types and tables" do
    Application.put_env(:logger, :level, :info)

    {:ok, _} = Xandra.start_link(name: :xandra_conn, nodes: ["127.0.0.1:9042"])
    assert :ok = SchemaMigrator.run()

    assert {:ok, %Xandra.Page{}} =
             Xandra.execute(:xandra_conn, "select * from uniris.transaction_chains;")

    assert {:ok, %Xandra.Page{}} =
             Xandra.execute(:xandra_conn, "select * from uniris.transactions;")
  end
end
