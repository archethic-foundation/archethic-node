defmodule UnirisP2P.Application do
  @moduledoc false

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

    Supervisor.start_link(children, strategy: :one_for_one, name: UnirisP2P.Supervisor)
  end
end
