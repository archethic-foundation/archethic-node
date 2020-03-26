defmodule UnirisSync.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: UnirisSync.Supervisor]

    children = [
      {Registry, keys: :duplicate, name: UnirisSync.PubSub},
      {UnirisSync.SelfRepair,
       [
         last_sync_date: Application.get_env(:uniris_sync, :last_sync_date),
         repair_interval: Application.get_env(:uniris_sync, :self_repair_interval)
       ]},
      UnirisSync.TransactionLoader,
      {UnirisSync.Bootstrap, port: Application.get_env(:uniris_p2p_server, :port)}
    ]

    Supervisor.start_link(children, opts)
  end
end
