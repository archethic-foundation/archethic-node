defmodule ArchEthic.DB.CassandraImpl.SchemaMigrator do
  @moduledoc false

  alias ArchEthic.DB.CassandraImpl

  require Logger

  use GenServer

  require CassandraImpl

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_) do
    {:ok, client} = :cqerl.get_client()

    run(client)
    {:ok, []}
  end

  @doc """
  Run the Cassandra schema migrations
  """
  def run(client) do
    client
    |> prepare_keyspace()
    |> load_migrations()
  end

  defp prepare_keyspace(client) do
    client
    |> create_keyspace()
    |> create_migration_table()
  end

  defp create_keyspace(client) do
    :cqerl.run_query(client, """
      CREATE KEYSPACE IF NOT EXISTS archethic WITH replication = {
        'class': 'SimpleStrategy',
        'replication_factor' : 1
      };
    """)

    client
  end

  defp create_migration_table(client) do
    :cqerl.run_query(client, """
    CREATE TABLE IF NOT EXISTS archethic.schema_migrations(
      version INT,
      updated_at TIMESTAMP,
      PRIMARY KEY (version)
    );
    """)

    client
  end

  defp load_migrations(client) do
    migrated_versions = get_migrated_versions(client)

    get_migrations()
    |> Enum.map(&load_migration/1)
    |> Enum.reject(fn {version, _, _} -> version in migrated_versions end)
    |> run_migrations(client)
    |> register_migrated_versions(client)
  end

  defp get_migrated_versions(client) do
    {:ok, result} = :cqerl.run_query(client, "SELECT version FROM archethic.schema_migrations")

    result
    |> :cqerl.all_rows()
    |> Enum.map(&Keyword.get(&1, :version))
  end

  defp get_migrations do
    migration_path()
    |> Path.join(["**", "*.cql"])
    |> Path.wildcard()
    |> Enum.map(&extract_migration_info/1)
    |> Enum.filter(& &1)
    |> Enum.sort()
  end

  defp migration_path do
    Application.app_dir(:archethic, "priv/migrations")
  end

  defp extract_migration_info(file) do
    base = Path.basename(file)

    case Integer.parse(Path.rootname(base)) do
      {integer, "_" <> name} -> {integer, name, file}
      _ -> nil
    end
  end

  defp load_migration({version, name, file}) do
    migration_script =
      file
      |> File.read!()
      |> String.replace("\n", "")

    {version, migration_script, name}
  end

  defp run_migrations(migrations, client) do
    for {version, migration_query, name} <- migrations do
      Logger.debug("Execute migration from #{name}")

      migration_query
      |> String.split(";", trim: true)
      |> Enum.each(&:cqerl.run_query(client, &1))

      version
    end
  end

  defp register_migrated_versions([], _) do
    Logger.debug("No new migrations to execute or register")
  end

  defp register_migrated_versions(versions, client) do
    query = "INSERT INTO archethic.schema_migrations(version, updated_at) VALUES(?, ?)"

    Enum.each(versions, fn version ->
      query =
        CassandraImpl.cql_query(
          statement: query,
          values: [
            version: version,
            updated_at: DateTime.to_unix(DateTime.utc_now(), :millisecond)
          ]
        )

      {:ok, _} = :cqerl.run_query(client, query)
    end)
  end
end
