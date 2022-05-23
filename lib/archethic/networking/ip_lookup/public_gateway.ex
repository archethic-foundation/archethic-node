defmodule Archethic.Networking.IPLookup.PublicGateway do
  @moduledoc false
  @behaviour Archethic.Networking.IPLookup.Impl

  defdelegate get_node_ip, to: Archethic.Networking.IPLookup.IPIFY, as: :get_node_ip
end
