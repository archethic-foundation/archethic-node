defmodule ArchethicWeb.RootController do
  @moduledoc false

  use ArchethicWeb, :controller

  alias ArchethicWeb.Domain
  alias ArchethicWeb.API.WebHostingController

  def index(conn = %Plug.Conn{host: host}, params) do
    case Domain.lookup_dnslink_address(host) do
      {:error, :not_found} ->
        redirect(conn, to: "/explorer")

      {:ok, address} ->
        redirect_to_last_transaction_content(address, conn, params)
    end
  end

  defp redirect_to_last_transaction_content(address, conn, params) do
    params =
      params
      |> Map.put("address", address)
      |> Map.put("mime", "text/html")
      |> Map.put("url_path", Map.get(params, "path", []))

    cache_headers = WebHostingController.get_cache_headers(conn)

    case WebHostingController.get_website(params, cache_headers) do
      {:ok, file_content, encodage, mime_type, cached?, etag} ->
        WebHostingController.send_response(conn, file_content, encodage, mime_type, cached?, etag)

      _ ->
        redirect(conn, to: "/explorer")
    end
  end
end
