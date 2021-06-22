defmodule ArchEthicWeb.RootController do
  @moduledoc false

  use ArchEthicWeb, :controller

  alias ArchEthicWeb.API.TransactionController

  def index(conn, params) do
    case get_dnslink_address(conn) do
      nil ->
        redirect(conn, to: "/explorer")

      address ->
        redirect_to_last_transaction_content(address, conn, params)
    end
  end

  defp get_dnslink_address(conn) do
    conn
    |> get_req_header("host")
    |> get_extract_dnslink_address_from_host_header()
  end

  defp get_extract_dnslink_address_from_host_header([]), do: nil

  defp get_extract_dnslink_address_from_host_header([host]) do
    dns_name =
      host
      |> to_string()
      |> String.split(":")
      |> List.first()

    case :inet_res.lookup('_dnslink.#{dns_name}', :in, :txt) do
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

    TransactionController.last_transaction_content(conn, params)
  end
end
