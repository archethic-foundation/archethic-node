defmodule Uniris.P2P.Supervisor do
  @moduledoc false

  alias Uniris.P2P.BootstrappingSeeds
  alias Uniris.P2P.ConnectionPool.Supervisor, as: ConnectionPoolSupervisor
  alias Uniris.P2P.Endpoint
  alias Uniris.P2P.MemTable
  alias Uniris.P2P.MemTableLoader

  alias Uniris.Utils

  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: Uniris.P2PSupervisor)
  end

  def init(args) do
    port = Keyword.fetch!(args, :port)

    endpoint_conf = Application.get_env(:uniris, Endpoint)

    bootstrapping_seeds_file =
      Application.get_env(:uniris, BootstrappingSeeds, []) |> Keyword.fetch!(:file)

    optional_children = [
      ConnectionPoolSupervisor,
      MemTable,
      MemTableLoader,
      {Endpoint, [{:port, port} | endpoint_conf]},
      {BootstrappingSeeds, [file: Utils.mut_dir(bootstrapping_seeds_file)]}
    ]

    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
