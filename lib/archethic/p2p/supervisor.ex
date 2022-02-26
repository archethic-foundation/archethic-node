defmodule ArchEthic.P2P.Supervisor do
  @moduledoc false

  alias ArchEthic.P2P.BootstrappingSeeds
  alias ArchEthic.P2P.Client.ConnectionRegistry
  alias ArchEthic.P2P.Client.ConnectionSupervisor
  alias ArchEthic.P2P.Listener
  alias ArchEthic.P2P.MemTable
  alias ArchEthic.P2P.MemTableLoader

  alias ArchEthic.Utils

  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: ArchEthic.P2PSupervisor)
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
      {BootstrappingSeeds, bootstraping_seeds_conf}
    ]

    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
