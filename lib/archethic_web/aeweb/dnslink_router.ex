defmodule ArchethicWeb.DNSLinkRouter do
  @moduledoc """
  Catch dns link redirection for AEWeb and call WebHostingController
  """

  alias ArchethicWeb.AEWeb.Domain
  alias ArchethicWeb.AEWeb.WebHostingController

  @behaviour Plug

  def init(opts), do: opts

  def call(conn = %Plug.Conn{host: host, method: "GET", path_info: url_path}, _) do
    case get_dnslink_address(host) do
      {:ok, address} ->
        WebHostingController.web_hosting(conn, %{"address" => address, "url_path" => url_path})

      _ ->
        throw("No DNSLink defined")
    end
  end

  def call(_conn, _), do: throw("No DNSLink defined")

  defp get_dnslink_address(host) do
    if is_ip_address?(host), do: {:error, :ip_address}, else: Domain.lookup_dnslink_address(host)
  end

  defp is_ip_address?(host),
    do: {:ok, _ip} |> match?(host |> String.to_charlist() |> :inet.parse_address())
end
