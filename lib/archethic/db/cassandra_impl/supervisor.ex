defmodule ArchEthic.DB.CassandraImpl.Supervisor do
  @moduledoc false

  use Supervisor

  alias ArchEthic.DB.CassandraImpl.SchemaMigrator

  require Logger

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args)
  end

  def init(_args) do
    host = Application.get_env(:archethic, ArchEthic.DB.CassandraImpl) |> Keyword.fetch!(:host)

    Logger.info("Start Cassandra connection at #{host}")

    :cqerl_cluster.add_nodes([host])

    children = [
      SchemaMigrator
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
