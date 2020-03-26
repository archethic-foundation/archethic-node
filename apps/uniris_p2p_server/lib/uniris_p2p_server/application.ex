defmodule UnirisP2PServer.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    port = Application.get_env(:uniris_p2p_server, :port)

    children = [
      {Task.Supervisor, name: UnirisP2PServer.TaskSupervisor},
      {UnirisP2PServer, port}
    ]

    opts = [strategy: :one_for_one, name: UnirisP2PServer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
