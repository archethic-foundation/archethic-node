defmodule ArchethicWeb.Explorer.ExplorerRootController do
  @moduledoc false

  use ArchethicWeb.Explorer, :controller

  # def index(conn, _params), do: redirect(conn, to: "/explorer")
  def index(conn, _params) do
    case get_web_hosting_address(conn) do
      nil ->
        redirect(conn, to: "/explorer")

      address ->
        path =
          case Map.get(conn, :request_path, "/") do
            "" -> "/"
            path -> path
          end

        redirect(conn, to: "/api/web_hosting/" <> address <> path)
    end
  end

  def return_404(conn, _params), do: send_resp(conn, 404, "Not found")

  defp get_web_hosting_address(conn) do
    case get_req_header(conn, "referer") do
      [] ->
        nil

      [referer] ->
        case Regex.scan(~r/(?<=\/api\/web_hosting\/)[^\/]*/, referer) do
          [] ->
            nil

          [match] ->
            List.first(match)
        end
    end
  end
end
