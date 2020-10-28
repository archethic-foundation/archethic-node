defmodule Uniris.P2P.Supervisor do
  @moduledoc false

  alias Uniris.P2P.BootstrappingSeeds
  alias Uniris.P2P.Endpoint
  alias Uniris.P2P.MemTable
  alias Uniris.P2P.MemTableLoader

  alias Uniris.Utils

  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: Uniris.P2PSupervisor)
  end

  def init(_args) do
    bootstrapping_seeds_file = Application.get_env(:uniris, BootstrappingSeeds, [])[:file]

    optional_children = [
      MemTable,
      MemTableLoader,
      {Endpoint, Application.get_env(:uniris, Endpoint)},
      {BootstrappingSeeds, [file: Application.app_dir(:uniris, bootstrapping_seeds_file)]}
    ]

    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
