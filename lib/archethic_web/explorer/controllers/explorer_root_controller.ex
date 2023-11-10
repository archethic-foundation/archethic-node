defmodule ArchethicWeb.Explorer.ExplorerRootController do
  @moduledoc false

  alias Archethic.Crypto

  use ArchethicWeb.Explorer, :controller

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

        redirect(conn, to: "/aeweb/" <> address <> path)
    end
  end

  def return_404(conn, _params), do: send_resp(conn, 404, "Not found")

  defp get_web_hosting_address(conn) do
    case get_req_header(conn, "referer") do
      [] -> nil
      [referer] -> get_referer_address(referer)
    end
  end

  defp get_referer_address(referer) do
    with address_hex when is_binary(address_hex) <- extract_address(referer),
         {:ok, address} <- Base.decode16(address_hex, case: :mixed),
         true <- Crypto.valid_address?(address) do
      address_hex
    else
      _ -> nil
    end
  end

  defp extract_address(referer) do
    with [] <- Regex.scan(~r/(?<=\/api\/web_hosting\/)[^\/]*/, referer),
         [] <- Regex.scan(~r/(?<=\/aeweb\/)[^\/]*/, referer) do
      nil
    else
      [match] -> List.first(match)
    end
  end
end
