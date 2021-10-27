defmodule ArchEthic.DB.CassandraImpl.SchemaMigratorTest do
  use ExUnit.Case

  alias ArchEthic.DB.CassandraImpl.SchemaMigrator

  setup do
    Logger.configure(level: :debug)

    Code.compiler_options(ignore_module_conflict: true)

    :cqerl_cluster.add_nodes(["127.0.0.1:9042"])

    {:ok, client} = :cqerl.get_client()
    {:ok, _} = :cqerl.run_query(client, "DROP KEYSPACE IF EXISTS archethic")

    on_exit(fn ->
      Code.compiler_options(ignore_module_conflict: false)
    end)

    {:ok, %{client: client}}
  end

  describe "run/1" do
    @tag infrastructure: true
    test "should create all the user types and tables", %{client: client} do
      assert :ok = SchemaMigrator.run(client)

      {:ok, _} = :cqerl.run_query(client, "SELECT * FROM archethic.transactions")
    end

    @tag infrastructure: true
    test "should not rerun the migrations is the migrations was already executed", %{
      client: client
    } do
      assert :ok = SchemaMigrator.run(client)

      {:ok, result} =
        :cqerl.run_query(client, "SELECT updated_at FROM archethic.schema_migrations")

      updated_times =
        result
        |> :cqerl.all_rows()
        |> Enum.map(&Map.get(&1, "updated_at"))

      Process.sleep(1_000)

      assert :ok = SchemaMigrator.run(client)

      {:ok, result} =
        :cqerl.run_query(client, "SELECT updated_at FROM archethic.schema_migrations")

      updated_times2 =
        result
        |> :cqerl.all_rows()
        |> Enum.map(&Map.get(&1, "updated_at"))

      assert updated_times2 == updated_times
    end
  end
end
