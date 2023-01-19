defmodule Mix.Tasks.Archethic.CleanDb do
  @moduledoc "Drop all the data from the database"

  use Mix.Task

  def run(_arg) do
    Application.get_env(:archethic, :root_mut_dir)
    |> File.rm_rf!()

    IO.puts("Database dropped")
  end
end
