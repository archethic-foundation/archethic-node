defmodule Uniris.Networking.IPLookup do
  @moduledoc false

  # Public

  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, :invalid_ip_provider | :not_recognizable_ip | :ip_discovery_error}
  def get_node_ip do
    with config <- Application.get_env(:uniris, Uniris.Networking),
    {:ok, ip_provider} <- Keyword.fetch(config, :ip_provider) do
      ip_provider.get_node_ip()
    else
      :error -> {:error, :invalid_ip_provider} 
      {:error, :not_recognizable_ip} -> {:error, :not_recognizable_ip}
    end
  end
end