defmodule Uniris.P2PSupervisor do
  @moduledoc false

  alias Uniris.P2P.BootstrapingSeeds
  alias Uniris.P2P.Endpoint
  alias Uniris.P2P.GeoPatch
  alias Uniris.P2P.NodeViewSupervisor

  alias Uniris.Utils

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    port = Application.get_env(:uniris, Uniris.P2P.Endpoint)[:port]
    bootstraping_seeds_file = Application.get_env(:uniris, BootstrapingSeeds, [])[:file]

    children =
      [
        GeoPatch,
        NodeViewSupervisor
      ] ++
        Utils.configurable_children([
          {Endpoint, [port: port], []},
          {BootstrapingSeeds, [file: Application.app_dir(:uniris, bootstraping_seeds_file)], []}
        ])

    Supervisor.init(children, strategy: :one_for_one)
  end
end
