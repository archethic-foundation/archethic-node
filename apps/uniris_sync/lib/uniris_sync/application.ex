defmodule UnirisSync.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: UnirisSync.Supervisor]
    Supervisor.start_link(children_by_env(Mix.env()), opts)
  end

  defp children_by_env(:test) do
    [
      UnirisSync.TransactionLoader,
      {Registry, keys: :unique, name: UnirisSync.BeaconSubsetRegistry},
    ]
  end

  defp children_by_env(_) do

    subsets = UnirisSync.Beacon.all_subsets()

    [
      {Registry, keys: :duplicate, name: UnirisSync.PubSub},
      {Registry, keys: :unique, name: UnirisSync.BeaconSubsetRegistry},
      UnirisSync.TransactionLoader,
      {UnirisSync.Bootstrap,
       [
         ip: Application.get_env(:uniris_p2p, :ip),
         port: Application.get_env(:uniris_p2p, :port)
       ]},
      {UnirisSync.SelfRepair,
       [
         last_sync_date: Application.get_env(:uniris_sync, :last_sync_date),
         beacon_slot_interval: Application.get_env(:uniris_sync, :beacon_slot_interval),
         repair_interval: Application.get_env(:uniris_sync, :self_repair_interval),
         subsets: subsets
       ]},
      {UnirisSync.Beacon,
       startup_date: Application.get_env(:uniris_sync, :last_sync_date),
       slot_interval: Application.get_env(:uniris_sync, :beacon_slot_interval),
       subsets: subsets
      }
    ]
  end

end
