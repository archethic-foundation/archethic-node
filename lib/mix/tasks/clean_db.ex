defmodule Mix.Tasks.Archethic.CleanDb do
  @moduledoc "Drop all the data from the database"

  use Mix.Task

  def run(_arg) do
    "_build/dev/lib/archethic/data*"
    |> Path.wildcard()
    |> Enum.each(fn path ->
      IO.puts("#{path} will be removed")
      File.rm_rf!(path)
    end)

    IO.puts("Database dropped")
  end
end
