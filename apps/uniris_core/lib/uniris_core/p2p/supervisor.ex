defmodule UnirisCore.P2PSupervisor do
  @moduledoc false

  alias UnirisCore.P2PServer
  alias UnirisCore.P2P.GeoPatch
  alias UnirisCore.P2P.NodeViewSupervisor
  alias UnirisCore.P2P.BootstrapingSeeds
  alias UnirisCore.Utils

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    port = Application.get_env(:uniris_core, UnirisCore.P2P) |> Keyword.fetch!(:port)

    bootstraping_seeds_file =
      :uniris_core
      |> Application.get_env(BootstrapingSeeds, [])
      |> Keyword.get(:file, "priv/p2p/last_sync")

    children =
      [
        {P2PServer, port: port},
        GeoPatch,
        NodeViewSupervisor
      ] ++
        Utils.configurable_children([
          {BootstrapingSeeds, [file: Application.app_dir(:uniris_core, bootstraping_seeds_file)],
           []}
        ])

    Supervisor.init(children, strategy: :one_for_one)
  end
end
