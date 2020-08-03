defmodule Uniris.InterpreterSupervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.Interpreter.TransactionLoader
  alias Uniris.Utils

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children =
      [
        {Registry, keys: :unique, name: Uniris.ContractRegistry},
        {DynamicSupervisor, strategy: :one_for_one, name: Uniris.ContractSupervisor}
      ] ++ Utils.configurable_children([{TransactionLoader, [], []}])

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
