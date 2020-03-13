defmodule UnirisChain.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    :ets.new(:ko_transactions, [:named_table, :public])

    children = [
      UnirisChain,
      {Registry, keys: :unique, name: UnirisChain.TransactionRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: UnirisChain.TransactionSupervisor}
    ]

    opts = [strategy: :one_for_one, name: UnirisChain.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
