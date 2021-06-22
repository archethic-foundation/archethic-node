defmodule ArchEthic.P2P.Endpoint.Supervisor do
  @moduledoc false

  use Supervisor

  alias ArchEthic.P2P.Endpoint.Listener
  alias ArchEthic.Utils

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    static_children = [
      {Task.Supervisor, strategy: :one_for_one, name: ArchEthic.P2P.Endpoint.ConnectionSupervisor}
    ]

    optional_children = [
      {Listener, args, []}
    ]

    Supervisor.init(static_children ++ Utils.configurable_children(optional_children),
      strategy: :one_for_one
    )
  end
end
