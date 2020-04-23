defmodule UnirisCore.P2PSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    port = Application.get_env(:uniris_core, UnirisCore.P2P) |> Keyword.fetch!(:port)

    children = [
      {UnirisCore.P2PServer, port: port},
      UnirisCore.P2P.GeoPatch,
      UnirisCore.P2P.NodeViewSupervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
