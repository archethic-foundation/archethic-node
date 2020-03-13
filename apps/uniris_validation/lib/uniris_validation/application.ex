defmodule UnirisValidation.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: UnirisValidation.MiningRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: UnirisValidation.MiningSupervisor},
      {Task.Supervisor, name: UnirisValidation.TaskSupervisor}
    ]

    opts = [strategy: :one_for_one, name: UnirisValidation.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
