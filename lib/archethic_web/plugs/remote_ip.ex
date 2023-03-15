defmodule ArchethicWeb.Plugs.RemoteIP do
  @moduledoc """
  Get actual behind the reverse proxy IP address
  """

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _) do
    conn
    |> Plug.Conn.get_req_header("x-forwarded-for")
    |> List.first()
    |> parse_ip(conn)
  end

  defp parse_ip(nil, conn), do: conn

  defp parse_ip(ip_list, conn) do
    ip_str =
      String.split(ip_list, ",")
      |> List.first()
      |> String.trim()
      |> String.to_charlist()

    case :inet.parse_address(ip_str) do
      {:ok, ip} -> Map.put(conn, :remote_ip, ip)
      _ -> conn
    end
  end
end
