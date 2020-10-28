defmodule Uniris.Contracts.Supervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.Contracts.Loader

  alias Uniris.Utils

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: Uniris.ContractsSupervisor)
  end

  def init(_args) do
    optional_children = [{Loader, [], []}]

    static_children = [
      {Registry, keys: :unique, name: Uniris.ContractRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Uniris.ContractSupervisor}
    ]

    children = static_children ++ Utils.configurable_children(optional_children)
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
