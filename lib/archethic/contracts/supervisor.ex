defmodule Archethic.Contracts.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.Contracts.Loader

  alias Archethic.Utils

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: Archethic.ContractsSupervisor)
  end

  def init(_args) do
    optional_children = [{Loader, [], []}]

    static_children = [
      {Registry, keys: :unique, name: Archethic.ContractRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Archethic.ContractSupervisor}
    ]

    children = static_children ++ Utils.configurable_children(optional_children)
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
