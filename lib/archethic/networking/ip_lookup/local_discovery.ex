defmodule Archethic.Networking.IPLookup.LocalDiscovery do
  @moduledoc false

  use Knigge,
    otp_app: :archethic,
    default: Archethic.Networking.IPLookup.NAT

  @callback get_node_ip() :: {:ok, :inet.ip_address()} | {:error, :ip_discovery_error}
end
