defmodule UnirisP2P.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: UnirisP2P.NodeRegistry},
      {Registry, keys: :unique, name: UnirisP2P.ConnectionRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: UnirisP2P.NodeSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: UnirisP2P.ConnectionSupervisor},
      UnirisP2P.GeoPatch,
      {UnirisP2P.SeedLoader, [seed_file: Application.app_dir(:uniris_p2p, "priv/seed.txt")]}
    ]

    opts = [strategy: :one_for_one, name: UnirisP2P.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
