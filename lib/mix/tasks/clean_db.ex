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

    Application.ensure_all_started(:cqerl)
    :cqerl_cluster.add_nodes([host])

    {:ok, client} = :cqerl.get_client()
    {:ok, _} = :cqerl.run_query(client, "DROP KEYSPACE IF EXISTS archethic;")
    IO.puts("Database #{host} dropped")
  end
end
