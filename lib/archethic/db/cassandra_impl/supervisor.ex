defmodule ArchEthic.DB.CassandraImpl.Supervisor do
  @moduledoc false

  use Supervisor

  alias ArchEthic.DB.CassandraImpl.QueryPipeline
  alias ArchEthic.DB.CassandraImpl.SchemaMigrator

  require Logger

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args)
  end

  def init(_args) do
    conf = Application.get_env(:archethic, ArchEthic.DB.CassandraImpl)

    host = Keyword.fetch!(conf, :host)
    pool_size = Keyword.get(conf, :pool_size, 10)

    Logger.info("Start Cassandra connection at #{host}")

    children = [
      {Xandra, name: :xandra_conn, pool_size: pool_size, nodes: [host]},
      QueryPipeline,
      SchemaMigrator
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
