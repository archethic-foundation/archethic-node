defmodule ArchethicWeb.RouterDispatch do
  @moduledoc """
  This module is used to dispatch the connection between multiple routers
  """

  @behaviour Plug
  require Logger

  def init(opts), do: opts

  def call(conn, opts) do
    routers = Keyword.get(opts, :routers, [])

    # here we catch the NoRouteError and the NoDNSLink error
    # to continue try routers
    # all others error are logged
    Enum.reduce_while(routers, conn, fn router, _acc ->
      try do
        conn = router.call(conn, [])
        {:halt, conn}
      rescue
        Phoenix.Router.NoRouteError ->
          {:cont, conn}

        e ->
          {:halt, conn |> send_error(e, __STACKTRACE__)}
      catch
        "No DNSLink defined" ->
          {:cont, conn}

        e ->
          {:halt, conn |> send_error(e, __STACKTRACE__)}
      end
    end)
  end

  defp send_error(conn, e, stacktrace) do
    Logger.error(Exception.format(:error, e, stacktrace))

    conn
    |> Plug.Conn.put_status(500)
    |> Phoenix.Controller.json(%{"error" => "internal error"})
  end
end
