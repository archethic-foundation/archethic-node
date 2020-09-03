defmodule Uniris.StorageSupervisor do
  @moduledoc false

  alias Uniris.Storage.Backend
  alias Uniris.Storage.MemorySupervisor

  alias Uniris.Utils

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children =
      Utils.configurable_children([
        {Backend, [], []},
        {MemorySupervisor, [], []}
      ])

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
