defmodule UnirisCore.Storage.CassandraBackend.ChainQuerySupervisor do
  @moduledoc false

  use Supervisor

  alias UnirisCore.Storage.CassandraBackend.ChainQueryWorker

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    children = Enum.map(0..10, fn i ->
      Supervisor.child_spec({ChainQueryWorker, [bucket: i]}, [id: i])
    end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
