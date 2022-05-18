defmodule Archethic.Networking.IPLookup.PublicIPGatewayImpl do
  @moduledoc false

  defmacro __using__(_) do
    quote do
      def get_node_ip() do
        Logger.info("Trying IPFY as fallback")
        Archethic.Networking.IPLookup.IPIFY.get_node_ip()
        defoverridable get_node_ip: 0
      end
    end
  end

  @callback get_node_ip() :: {:ok, :inet.ip_address()} | {:error, any()}
end
