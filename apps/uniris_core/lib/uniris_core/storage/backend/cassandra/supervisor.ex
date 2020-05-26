defmodule UnirisCore.Storage.CassandraBackend.Supervisor do
  @moduledoc false

  use Supervisor
  alias UnirisCore.Storage.CassandraBackend.SchemaMigrator

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      {Xandra, name: :xandra_conn, nodes: ["127.0.0.1:9042"]},
      SchemaMigrator
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
