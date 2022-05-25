defmodule Archethic.Networking.IPLookup.NATDiscovery.UPnPv1 do
  @moduledoc false
  alias Archethic.Networking.IPLookup.Impl

  @behaviour Impl

  @impl Impl
  @spec get_node_ip :: {:error, any()} | {:ok, :inet.ip_address()}
  def get_node_ip() do
    with {:ok, router_ip} <- :natupnp_v1.discover(),
         {:ok, ip_chars} <- :natupnp_v1.get_external_address(router_ip) do
      :inet.parse_address(ip_chars)
    end
  end
end
