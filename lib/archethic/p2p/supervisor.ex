defmodule ArchEthic.P2P.Supervisor do
  @moduledoc false

  alias ArchEthic.P2P.BootstrappingSeeds
  alias ArchEthic.P2P.Connection
  alias ArchEthic.P2P.Endpoint
  alias ArchEthic.P2P.Endpoint.Supervisor, as: EndpointSupervisor
  alias ArchEthic.P2P.MemTable
  alias ArchEthic.P2P.MemTableLoader

  alias ArchEthic.Utils

  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: ArchEthic.P2PSupervisor)
  end

  def init(args) do
    port = Keyword.fetch!(args, :port)

    endpoint_conf = Application.get_env(:archethic, Endpoint, [])

    bootstraping_seeds_conf = Application.get_env(:archethic, BootstrappingSeeds)

    # Setup the connection handler for the local node
    Connection.start_link(name: ArchEthic.P2P.LocalConnection, initiator?: true)

    optional_children = [
      {Registry,
       keys: :unique,
       name: ArchEthic.P2P.ConnectionRegistry,
       partitions: System.schedulers_online()},
      {DynamicSupervisor, name: ArchEthic.P2P.ConnectionSupervisor, strategy: :one_for_one},
      MemTable,
      MemTableLoader,
      {EndpointSupervisor, Keyword.put(endpoint_conf, :port, port)},
      {BootstrappingSeeds,
       [
         backup_file: Utils.mut_dir(Keyword.fetch!(bootstraping_seeds_conf, :backup_file)),
         genesis_seeds: Keyword.get(bootstraping_seeds_conf, :genesis_seeds)
       ]}
    ]

    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
