defmodule UnirisPubSub.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :duplicate, name: UnirisPubSub.Registry},
    ]

    opts = [strategy: :one_for_one, name: UnirisPubSub.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
