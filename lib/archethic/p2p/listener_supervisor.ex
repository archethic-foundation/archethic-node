defmodule Archethic.P2P.ListenerSupervisor do
  @moduledoc false

  alias Archethic.P2P.BootstrappingSeeds
  alias Archethic.P2P.Listener

  alias Archethic.Utils

  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: Archethic.P2PListenerSupervisor)
  end

  def init(args) do
    port = Keyword.fetch!(args, :port)

    listener_conf = Application.get_env(:archethic, Listener, [])

    bootstraping_seeds_conf = Application.get_env(:archethic, BootstrappingSeeds)

    optional_children = [
      {Listener, Keyword.put(listener_conf, :port, port)},
      {BootstrappingSeeds, bootstraping_seeds_conf}
    ]

    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
