defmodule Uniris.Networking.IPLookup do
  @moduledoc false

  alias __MODULE__.Config

  # Public

  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, binary}
  def get_node_ip do
    with {:ok, ip_provider} <- Config.ip_provider() do
      ip_provider.get_node_ip()
    else
      {:error, reason} -> {:error, reason}
    end
  end
end