defmodule ArchethicWeb.RouterDispatch do
  @moduledoc """
  This module is used to dispatch the connection to the right route.
  If the connection contains a dnslink redirection aeweb route is used, otherwise explorer route is used
  """

  alias ArchethicWeb.Domain
  alias ArchethicWeb.AEWebRouter
  alias ArchethicWeb.ExplorerRouter

  @behaviour Plug

  def init(opts \\ []) do
    Enum.into(opts, %{})
  end

  def call(conn = %Plug.Conn{host: host}, params) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, _ip} ->
        ExplorerRouter.call(conn, params)

      {:error, _} ->
        resolve_domain_name(conn, params)
    end
  end

  defp resolve_domain_name(conn = %Plug.Conn{host: "localhost"}, params),
    do: ExplorerRouter.call(conn, params)

  defp resolve_domain_name(conn = %Plug.Conn{host: host}, params) do
    case Domain.lookup_dnslink_address(host) do
      {:error, :not_found} ->
        ExplorerRouter.call(conn, params)

      {:ok, address} ->
        conn = Map.update!(conn, :params, &Map.put(&1, "address", address))
        AEWebRouter.call(conn, params)
    end
  end
end
