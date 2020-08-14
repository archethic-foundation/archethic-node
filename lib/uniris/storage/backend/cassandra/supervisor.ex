defmodule Uniris.Storage.CassandraBackend.Supervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.Storage.CassandraBackend.SchemaMigrator

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    nodes = Application.get_env(:uniris, Uniris.Storage.CassandraBackend)[:nodes]

    children = [
      {Xandra, name: :xandra_conn, nodes: nodes, pool_size: 10},
      SchemaMigrator
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
