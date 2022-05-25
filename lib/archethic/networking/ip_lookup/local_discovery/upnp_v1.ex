defmodule Archethic.Networking.IPLookup.NATDiscovery.UPnPv1 do
  @moduledoc false
  alias Archethic.Networking.IPLookup.Impl

  @behaviour Impl

  @impl Impl
  def get_node_ip() do
    with {:ok, router_ip} <- :natupnp_v1.discover(),
         {:ok, ip_chars} <- :natupnp_v1.get_external_address(router_ip),
         {:ok, ip} <- :inet.parse_address(ip_chars) do
      {ip}
    end
  end
end
