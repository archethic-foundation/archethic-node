defmodule Uniris.DB.CassandraImpl.Supervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.DB.CassandraImpl.Consumer
  alias Uniris.DB.CassandraImpl.Producer
  alias Uniris.DB.CassandraImpl.SchemaMigrator

  require Logger

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args)
  end

  def init(_args) do
    host = Application.get_env(:uniris, Uniris.DB.CassandraImpl) |> Keyword.fetch!(:host)

    Logger.info("Start Cassandra connection at #{host}")

    children = [
      {Xandra, name: :xandra_conn, pool_size: 10, nodes: [host]},
      Producer,
      Consumer,
      SchemaMigrator
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
