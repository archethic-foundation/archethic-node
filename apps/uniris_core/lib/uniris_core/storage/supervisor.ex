defmodule UnirisCore.StorageSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      UnirisCore.Storage.FileBackend,
      UnirisCore.Storage.Cache
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
