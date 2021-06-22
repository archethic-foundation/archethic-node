defmodule ArchEthic.DB.CassandraImpl.SchemaMigratorTest do
  use ExUnit.Case

  alias ArchEthic.DB.CassandraImpl.SchemaMigrator

  setup do
    Code.compiler_options(ignore_module_conflict: true)

    {:ok, _} = Xandra.start_link(name: :xandra_conn, nodes: ["127.0.0.1:9042"])
    Xandra.execute!(:xandra_conn, "DROP KEYSPACE IF EXISTS archethic")
    :ok

    on_exit(fn ->
      Code.compiler_options(ignore_module_conflict: false)
    end)
  end

  describe "run/1" do
    @tag infrastructure: true
    test "should create all the user types and tables" do
      assert :ok = SchemaMigrator.run()

      assert {:ok, %Xandra.Page{}} =
               Xandra.execute(:xandra_conn, "select * from archethic.transaction_chains;")

      assert {:ok, %Xandra.Page{}} =
               Xandra.execute(:xandra_conn, "select * from archethic.transactions;")
    end

    @tag infrastructure: true
    test "should not rerun the migrations is the migrations was already executed" do
      assert :ok = SchemaMigrator.run()

      updated_times =
        Xandra.execute!(:xandra_conn, "SELECT updated_at FROM archethic.schema_migrations")
        |> Enum.map(&Map.get(&1, "updated_at"))

      Process.sleep(1_000)

      assert :ok = SchemaMigrator.run()

      updated_times2 =
        Xandra.execute!(:xandra_conn, "SELECT updated_at FROM archethic.schema_migrations")
        |> Enum.map(&Map.get(&1, "updated_at"))

      assert updated_times2 == updated_times
    end
  end
end
