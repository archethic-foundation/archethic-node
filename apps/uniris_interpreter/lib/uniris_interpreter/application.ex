defmodule UnirisInterpreter.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: UnirisInterpreter.ContractRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: UnirisInterpreter.ContractSupervisor}
    ]

    Supervisor.start_link(children, strategy: :rest_for_one, name: UnirisInterpreter.Supervisor)
  end
end
