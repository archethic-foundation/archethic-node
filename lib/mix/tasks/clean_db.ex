defmodule Mix.Tasks.ArchEthic.CleanDb do
  @moduledoc "Drop all the data from the database"

  use Mix.Task

  def run(_arg) do
    files_to_remove =
      ["_build", "dev", "lib", "archethic", "data_*"]
      |> Path.join()
      |> Path.wildcard()

    IO.puts("#{files_to_remove} will be removed")

    Enum.each(files_to_remove, &File.rm_rf!/1)

    IO.puts("Database dropped")
  end
end
