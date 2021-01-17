defmodule Uniris.Networking.IPLookup do
  @moduledoc false

  alias __MODULE__.{Nat, Ipify}

  # Public

  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, :invalid_ip_provider | :not_recognizable_ip | :ip_discovery_error}
  def get_node_ip do
    with config when not is_nil(config) <- Application.get_env(:uniris, Uniris.Networking),
    {:ok, ip_provider} <- Keyword.fetch(config, :ip_provider) do
      ip_provider.get_node_ip()
    else
      nil -> get_external_ip()
      :error -> {:error, :invalid_ip_provider} 
      {:error, reason} -> {:error, reason}
    end
  end

  @spec get_external_ip() :: {:ok, :inet.ip_address()} | {:error, :invalid_ip_provider | :not_recognizable_ip | :ip_discovery_error}
  defp get_external_ip do
    with {:ok, ip} <- Nat.get_node_ip do
      {:ok, ip}
    else
      {:error, _} -> Ipify.get_node_ip()
    end
  end
end