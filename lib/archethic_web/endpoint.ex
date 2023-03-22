defmodule ArchethicWeb.Endpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :archethic
  use Absinthe.Phoenix.Endpoint

  require Logger

  plug(:archethic_up)

  plug(ArchethicWeb.Plugs.RemoteIP)

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_archethic_key",
    signing_salt: "wwLmAJji"
  ]

  socket("/socket", ArchethicWeb.UserSocket,
    websocket: true,
    longpoll: false
  )

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug(Plug.Static,
    at: "/",
    from: :archethic,
    gzip: true,
    only: ~w(css fonts images js favicon.ico robots.txt .well-known)
  )

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, {:json, length: 20_000_000}],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(CORSPlug, origin: "*")
  plug(ArchethicWeb.RouterDispatch)
  # don't serve anything before the node is bootstraped
  #
  # ps: this handle only HTTP(S) requests
  #     for WS, see archethic_web/channels/user_socket.ex
  defp archethic_up(conn, _opts) do
    if Archethic.up?() do
      conn
    else
      Logger.debug("Received a web request but node is bootstraping")

      conn
      |> send_resp(503, "")
      |> halt()
    end
  end
end
