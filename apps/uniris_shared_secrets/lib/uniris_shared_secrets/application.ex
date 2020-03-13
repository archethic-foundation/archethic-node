defmodule UnirisSharedSecrets.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      UnirisSharedSecrets
    ]

    opts = [strategy: :one_for_one, name: UnirisSharedSecrets.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
