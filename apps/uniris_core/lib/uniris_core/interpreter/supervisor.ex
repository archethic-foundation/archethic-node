defmodule UnirisCore.InterpreterSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: UnirisCore.ContractRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: UnirisCore.ContractSupervisor},
      UnirisCore.Interpreter.TransactionLoader
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
