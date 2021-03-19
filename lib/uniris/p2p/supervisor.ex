defmodule Uniris.P2P.Supervisor do
  @moduledoc false

  alias Uniris.P2P.Batcher
  alias Uniris.P2P.BootstrappingSeeds
  alias Uniris.P2P.Endpoint
  alias Uniris.P2P.Endpoint.Supervisor, as: EndpointSupervisor
  alias Uniris.P2P.MemTable
  alias Uniris.P2P.MemTableLoader

  alias Uniris.Utils

  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: Uniris.P2PSupervisor)
  end

  def init(args) do
    port = Keyword.fetch!(args, :port)

    endpoint_conf = Application.get_env(:uniris, Endpoint, [])

    bootstraping_seeds_conf = Application.get_env(:uniris, BootstrappingSeeds)

    optional_children = [
      {Registry,
       keys: :unique, name: Uniris.P2P.ConnectionRegistry, partitions: System.schedulers_online()},
      {DynamicSupervisor, name: Uniris.P2P.ConnectionSupervisor, strategy: :one_for_one},
      MemTable,
      MemTableLoader,
      {EndpointSupervisor, Keyword.put(endpoint_conf, :port, port)},
      {BootstrappingSeeds,
       [
         file: Utils.mut_dir(Keyword.fetch!(bootstraping_seeds_conf, :file)),
         seeds: Keyword.get(bootstraping_seeds_conf, :seeds)
       ]},
      {Batcher, []}
    ]

    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
