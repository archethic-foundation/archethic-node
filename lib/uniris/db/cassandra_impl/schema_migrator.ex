defmodule Uniris.DB.CassandraImpl.SchemaMigrator do
  @moduledoc false

  require Logger

  @doc """
  Run the Cassandra schema migrations
  """
  @spec run :: :ok
  def run do
    init()
    load_migrations()
  end

  defp init do
    create_keyspace()
    create_migration_table()
  end

  defp create_keyspace do
    Xandra.execute!(:xandra_conn, """
    CREATE KEYSPACE IF NOT EXISTS uniris WITH replication = {
      'class': 'SimpleStrategy',
      'replication_factor' : 1
    };
    """)
  end

  defp create_migration_table do
    Xandra.execute!(:xandra_conn, """
    CREATE TABLE IF NOT EXISTS uniris.schema_migrations(
      version INT,
      updated_at TIMESTAMP,
      PRIMARY KEY (version)
    );
    """)
  end

  defp load_migrations do
    migrated_versions = get_migrated_versions() |> Enum.map(&Map.get(&1, "version"))

    get_migrations()
    |> Enum.map(&load_migration/1)
    |> Enum.reject(fn {version, _} -> version in migrated_versions end)
    |> run_migrations()
    |> register_migrated_versions()
  end

  defp get_migrated_versions do
    Xandra.execute!(:xandra_conn, "SELECT version FROM uniris.schema_migrations")
  end

  defp get_migrations do
    migration_path()
    |> Path.join(["**", "*.exs"])
    |> Path.wildcard()
    |> Enum.map(&extract_migration_info/1)
    |> Enum.filter(& &1)
    |> Enum.sort()
  end

  defp migration_path do
    Application.app_dir(:uniris, "priv/migrations/cassandra")
  end

  defp extract_migration_info(file) do
    base = Path.basename(file)

    case Integer.parse(Path.rootname(base)) do
      {integer, "_" <> name} -> {integer, name, file}
      _ -> nil
    end
  end

  defp load_migration({version, _, file}) do
    loaded_modules = file |> Code.compile_file() |> Enum.map(&elem(&1, 0))

    if mod = Enum.find(loaded_modules, &migration?/1) do
      {version, mod}
    else
      raise "file #{Path.relative_to_cwd(file)} does not define execute/0"
    end

    {version, mod}
  end

  defp migration?(mod), do: function_exported?(mod, :execute, 0)

  defp run_migrations(migrations) do
    for {version, mod} <- migrations do
      Logger.debug("Execute migration #{version}.#{mod}")
      apply(mod, :execute, [])
      version
    end
  end

  defp register_migrated_versions([]) do
    Logger.debug("No new migrations to execute or register")
  end

  defp register_migrated_versions(versions) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "INSERT INTO uniris.schema_migrations(version, updated_at) VALUES(?, ?)"
      )

    Enum.each(versions, &Xandra.execute!(:xandra_conn, prepared, [&1, DateTime.utc_now()]))
  end
end
