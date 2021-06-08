defmodule Uniris.DB.CassandraImpl.Supervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.DB.CassandraImpl.Consumer
  alias Uniris.DB.CassandraImpl.Producer
  alias Uniris.DB.CassandraImpl.SchemaMigrator

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args)
  end

  def init(_args) do
    children = [
      {Xandra, name: :xandra_conn, pool_size: 10, nodes: ["127.0.0.1:9042"]},
      Producer,
      Consumer,
      SchemaMigrator
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
