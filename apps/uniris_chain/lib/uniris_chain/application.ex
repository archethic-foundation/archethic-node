defmodule UnirisChain.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      UnirisChain.TransactionStore.InMemory
    ]

    opts = [strategy: :one_for_one, name: UnirisChain.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
