defmodule UnirisSync.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :duplicate, name: UnirisSync.Registry},
      UnirisSync.TransactionSubscriber
    ]

    opts = [strategy: :one_for_one, name: UnirisSync.Supervisor]

    case Mix.env() do
      :test ->
        Supervisor.start_link(children, opts)

      _ ->
        (children ++
           [
             {UnirisSync.Bootstrap,
              [
                ip: Application.get_env(:uniris_p2p, :ip),
                port: Application.get_env(:uniris_p2p, :port)
              ]},
             {UnirisSync.SelfRepair,
              [interval: Application.get_env(:uniris_sync, :self_repair_interval)]}
           ])
        |> Supervisor.start_link(opts)
    end
  end
end
