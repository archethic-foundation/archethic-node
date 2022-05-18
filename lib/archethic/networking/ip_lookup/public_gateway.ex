defmodule Archethic.Networking.IPLookup.PublicGateway do
  use Knigge,
    otp_app: :archethic,
    default: Archethic.Networking.IPLookup.IPIFY

  @callback get_node_ip() :: {:ok, :inet.ip_address()} | {:error, :not_recognizable_ip}
end
