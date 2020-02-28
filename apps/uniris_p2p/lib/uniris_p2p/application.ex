defmodule UnirisP2P.Application do
  @moduledoc false

  require Logger

  use Application

  def start(_type, _args) do
    port = Application.get_env(:uniris_p2p, :port)

    children = [
      {Registry, keys: :unique, name: UnirisP2P.ClientRegistry},
      :ranch.child_spec(
        :p2p_server,
        :ranch_tcp,
        [{:port, port}],
        UnirisP2P.ConnectionHandler,
        []
      )
    ]

    Logger.info("P2P Server listening on port #{port}")

    Supervisor.start_link(children, strategy: :one_for_one, name: UnirisP2P.Supervisor)
  end
end
