defmodule Mix.Tasks.ArchEthic.CleanDb do
  @moduledoc "Drop all the data from the database"

  use Mix.Task

  def run(arg) do
    host =
      case(OptionParser.parse!(arg, strict: [host: :string])) do
        {[], []} ->
          "127.0.0.1:9042"

        {[host: host], []} ->
          host
      end

    {:ok, _started} = Application.ensure_all_started(:xandra)
    {:ok, conn} = Xandra.start_link(nodes: [host])
    Xandra.execute!(conn, "DROP KEYSPACE IF EXISTS archethic;")
    IO.puts("Database #{host} dropped")
  end
end
