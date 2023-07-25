defmodule ArchethicWeb.Plugs.ArchethicUp do
  @moduledoc """
  don't serve anything before the node is bootstraped

  ps: this handle only HTTP(S) requests
  for WS, see archethic_web/user_socket.ex
  """

  import Plug.Conn

  require Logger

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _) do
    request_path = Map.get(conn, :request_path, nil)

    if request_path in ["/metrics", "/metrics/"] or Archethic.up?() do
      conn
    else
      Logger.debug("Received a web request but node is bootstraping")

      conn
      |> send_resp(503, "")
      |> halt()
    end
  end
end
