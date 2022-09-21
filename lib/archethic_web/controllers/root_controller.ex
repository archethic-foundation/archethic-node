defmodule ArchethicWeb.RootController do
  @moduledoc false

  use ArchethicWeb, :controller

  alias ArchethicWeb.API.WebHostingController

  def index(conn = %Plug.Conn{host: host}, params) do
    case get_extract_dnslink_address(host) do
      nil ->
        redirect(conn, to: "/explorer")

      address ->
        redirect_to_last_transaction_content(address, conn, params)
    end
  end

  defp get_extract_dnslink_address(host) do
    dns_name =
      host
      |> to_string()
      |> String.split(":")
      |> List.first()

    case :inet_res.lookup('_dnslink.#{dns_name}', :in, :txt,
           # Allow local dns to test dnslink redirection
           alt_nameservers: [{{127, 0, 0, 1}, 53}]
         ) do
      [] ->
        nil

      [[dnslink_entry]] ->
        case Regex.scan(~r/(?<=dnslink=\/archethic\/).*/, to_string(dnslink_entry)) do
          [] ->
            nil

          [match] ->
            List.first(match)
        end
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
