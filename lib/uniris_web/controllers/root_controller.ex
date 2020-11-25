defmodule UnirisWeb.RootController do
  @moduledoc false

  use UnirisWeb, :controller

  alias UnirisWeb.API.TransactionController

  def index(conn, params) do
    case get_dnslink_address(conn) do
      nil ->
        redirect(conn, to: "/explorer")

      address ->
        redirect_to_last_transaction_content(address, conn, params)
    end
  end

  defp get_dnslink_address(conn) do
    [host] = get_req_header(conn, "host")

    case :inet_res.lookup('_dnslink.#{host}', :in, :txt) do
      [] ->
        nil

      [[dnslink_entry]] ->
        case Regex.scan(~r/(?<=dnslink=\/uniris\/).*/, to_string(dnslink_entry)) do
          [] ->
            nil

          [match] ->
            List.first(match)
        end
    end
  end

  defp redirect_to_last_transaction_content(address, conn, params) do
    params
    |> Map.put("address", address)
    |> Map.put("mime", "text/html")

    TransactionController.last_transaction_content(conn, params)
  end
end
