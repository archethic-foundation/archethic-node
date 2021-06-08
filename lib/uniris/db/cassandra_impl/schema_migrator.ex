defmodule Uniris.DB.CassandraImpl.SchemaMigrator do
  @moduledoc false

  alias Uniris.DB.CassandraImpl.Producer

  require Logger

  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_) do
    run()
    {:ok, []}
  end

  @doc """
  Run the Cassandra schema migrations
  """
  def run do
    init()
    load_migrations()
  end

  defp init do
    create_keyspace()
    create_migration_table()
  end

  defp create_keyspace do
    """
      CREATE KEYSPACE IF NOT EXISTS uniris WITH replication = {
        'class': 'SimpleStrategy',
        'replication_factor' : 1
      };
    """
    |> Producer.add_query()
  end

  defp create_migration_table do
    """
    CREATE TABLE IF NOT EXISTS uniris.schema_migrations(
      version INT,
      updated_at TIMESTAMP,
      PRIMARY KEY (version)
    );
    """
    |> Producer.add_query()
  end

  defp load_migrations do
    migrated_versions = Enum.map(get_migrated_versions(), &Map.get(&1, "version"))

    get_migrations()
    |> Enum.map(&load_migration/1)
    |> Enum.reject(fn {version, _, _} -> version in migrated_versions end)
    |> run_migrations()
    |> register_migrated_versions()
  end

  defp get_migrated_versions do
    Producer.add_query("SELECT version FROM uniris.schema_migrations")
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
    Application.app_dir(:uniris, "priv/migrations")
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

  defp run_migrations(migrations) do
    for {version, migration_query, name} <- migrations do
      Logger.debug("Execute migration from #{name}")

      migration_query
      |> String.split(";", trim: true)
      |> Enum.each(&Producer.add_query/1)

      version
    end
  end

  defp register_migrated_versions([]) do
    Logger.debug("No new migrations to execute or register")
  end

  defp register_migrated_versions(versions) do
    query = "INSERT INTO uniris.schema_migrations(version, updated_at) VALUES(?, ?)"

    Enum.each(versions, &Producer.add_query(query, [&1, DateTime.utc_now()]))
  end
end
