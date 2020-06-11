defmodule UnirisCore.Storage.CassandraBackend.Supervisor do
  @moduledoc false

  use Supervisor
  alias UnirisCore.Storage.CassandraBackend.SchemaMigrator
  alias UnirisCore.Storage.CassandraBackend.ChainQuerySupervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    nodes = Application.get_env(:uniris_core, UnirisCore.Storage.CassandraBackend)[:nodes]

    children = [
      {Xandra, name: :xandra_conn, nodes: nodes, pool_size: 10},
      SchemaMigrator,
      ChainQuerySupervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
