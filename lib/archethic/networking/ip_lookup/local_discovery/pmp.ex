defmodule Archethic.Networking.IPLookup.LocalDiscovery.PMP do
  @moduledoc false
  alias Archethic.Networking.IPLookup.Impl

  @behaviour Impl

  @impl Impl
  def get_node_ip() do
    with {:ok, router_ip} <- :natpmp.discover(),
         {:ok, ip_chars} <- :natpmp.get_external_address(router_ip),
         {:ok, ip} <- :inet.parse_address(ip_chars) do
      {:ok, ip}
    end
  end
end
