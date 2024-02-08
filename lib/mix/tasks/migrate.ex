defmodule Mix.Tasks.Archethic.Migrate do
  @moduledoc "Handle data migration"

  alias Archethic.DB.EmbeddedImpl
  alias Archethic.DB.EmbeddedImpl.ChainWriter

  alias Archethic.TaskSupervisor

  require Logger

  @env if Mix.env() == :test, do: "test", else: "prod"

  @doc """
  Run migration available migration scripts since last updated version
  """
  @spec run(binary(), boolean()) :: :ok
  def run(new_version, async? \\ false)

  def run(new_version, true) do
    Task.Supervisor.start_child(
      TaskSupervisor,
      fn -> do_run(new_version) end,
      shutdown: :brutal_kill
    )

    :ok
  end

  def run(new_version, false) do
    do_run(new_version)
  end

  defp do_run(new_version) do
    Logger.info("Start of migration task for version #{new_version}")
    migration_file_path = EmbeddedImpl.filepath() |> ChainWriter.migration_file_path()

    migrations_to_run =
      if File.exists?(migration_file_path) do
        read_file(migration_file_path) |> filter_migrations_to_run()
      else
        # File does not exist when it's the first time the node is started
        # We create the folder to write the migration file on first start
        migration_file_path |> Path.dirname() |> File.mkdir_p!()
        File.write(migration_file_path, new_version)
        []
      end

    Enum.each(migrations_to_run, fn {version, module} ->
      Logger.info("Run migration script for version #{version}")
      :erlang.apply(module, :run, [])
      unload_module(module)
      File.write(migration_file_path, version)
    end)

    Logger.info("End of migration task for version #{new_version}")
  end

  defp filter_migrations_to_run(last_version) do
    # List migration files, name must be version@description.exs
    # Then filter version higher than the last one runned
    # Eval the migration code and filter migration with function to call
    get_migrations_path()
    |> Enum.map(fn migration_path ->
      file_name = Path.basename(migration_path)
      migration_version = Regex.run(~r/.*(?=@)/, file_name) |> List.first()
      {migration_version, migration_path}
    end)
    |> Enum.filter(fn {migration_version, _} -> last_version < migration_version end)
    |> Enum.map(fn {version, path} -> {version, Code.eval_file(path)} end)
    |> Enum.filter(fn
      {_version, {{:module, module, _, _}, _}} ->
        if function_exported?(module, :run, 0) do
          true
        else
          unload_module(module)
          false
        end

      _ ->
        false
    end)
    |> Enum.map(fn {version, {{_, module, _, _}, _}} -> {version, module} end)
  end

  defp get_migrations_path() do
    Application.app_dir(:archethic)
    |> Path.join("priv/migration_tasks/#{@env}/*")
    |> Path.wildcard()
  end

  defp unload_module(module) do
    # Unload the module from code memory
    :code.purge(module)
    :code.delete(module)
  end

  defp read_file(path) do
    # handle old migration file format
    file_content = File.read!(path)

    if String.contains?(file_content, ";") do
      last_version = file_content |> String.split(";") |> Enum.reject(&(&1 == "")) |> List.last()
      File.write(path, last_version)
      last_version
    else
      file_content
    end
  end
end
