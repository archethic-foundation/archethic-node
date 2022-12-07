defmodule Mix.Tasks.Archethic.Migrate do
  @moduledoc "Handle data migration"

  use Mix.Task

  alias Archethic.DB.EmbeddedImpl
  alias Archethic.DB.EmbeddedImpl.ChainWriter

  def run(_arg) do
    version =
      :archethic
      |> Application.spec(:vsn)
      |> List.to_string()

    file_path = EmbeddedImpl.db_path() |> ChainWriter.migration_file_path()

    migration_done? =
      if File.exists?(file_path) do
        file_path |> File.read!() |> String.split(";") |> Enum.member?(version)
      else
        File.write(file_path, "#{version};", [:append])
        true
      end

    unless migration_done? do
      migrate(version)

      File.write!(file_path, "#{version};", [:append])
    end
  end

  defp migrate(_), do: :ok
end
