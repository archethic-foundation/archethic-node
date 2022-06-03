defmodule Archethic.P2P.Supervisor do
  @moduledoc false

  alias Archethic.P2P.BootstrappingSeeds
  alias Archethic.P2P.Client.ConnectionRegistry
  alias Archethic.P2P.Client.ConnectionSupervisor
  alias Archethic.P2P.Listener
  alias Archethic.P2P.MemTable
  alias Archethic.P2P.MemTableLoader
  alias Archethic.P2P.GeoPatch.GeoIP.IP2LocationImpl

  alias Archethic.Utils

  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: Archethic.P2PSupervisor)
  end

  def init(args) do
    port = Keyword.fetch!(args, :port)

    listener_conf = Application.get_env(:archethic, Listener, [])

    bootstraping_seeds_conf = Application.get_env(:archethic, BootstrappingSeeds)

    optional_children = [
      {Registry, name: ConnectionRegistry, keys: :unique},
      ConnectionSupervisor,
      MemTable,
      MemTableLoader,
      {Listener, Keyword.put(listener_conf, :port, port)},
      {BootstrappingSeeds, bootstraping_seeds_conf},
      IP2LocationImpl
    ]

    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
