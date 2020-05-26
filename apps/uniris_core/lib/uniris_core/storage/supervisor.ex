defmodule UnirisCore.StorageSupervisor do
  @moduledoc false

  alias UnirisCore.Utils

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children =
      Utils.configurable_children([
        {UnirisCore.Storage.CassandraBackend, [], []},
        {UnirisCore.Storage.Cache, [], []}
      ])

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
