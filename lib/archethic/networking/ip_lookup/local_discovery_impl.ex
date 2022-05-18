defmodule Archethic.Networking.IPLookup.LocalDiscoveryImpl do
  @moduledoc false

  defmacro __using__(_) do
    quote do
      def get_node_ip() do
        Archethic.Networking.IPLookup.NAT.get_node_ip()
        defoverridable get_node_ip: 0
      end
    end
  end

  @callback get_node_ip() :: {:ok, :inet.ip_address()} | {:error, any()}
end
