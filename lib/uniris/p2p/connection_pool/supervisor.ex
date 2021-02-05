defmodule Uniris.P2P.ConnectionPool.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_) do
    children = [
      {Registry, keys: :unique, name: Uniris.P2P.ConnectionPoolsRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Uniris.P2P.ConnectionPoolsSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
