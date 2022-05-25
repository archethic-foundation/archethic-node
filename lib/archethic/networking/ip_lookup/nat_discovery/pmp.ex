defmodule Archethic.Networking.IPLookup.NATDiscovery.PMP do
  @moduledoc false
  alias Archethic.Networking.IPLookup.Impl

  @behaviour Impl

  @impl Impl
  def get_node_ip() do
    with {:ok, router_ip} <- :natpmp.discover(),
         {:ok, ip_chars} <- :natpmp.get_external_address(router_ip) do
      :inet.parse_address(ip_chars)
    end
  end
end
