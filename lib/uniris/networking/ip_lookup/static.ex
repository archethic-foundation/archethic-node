defmodule Uniris.Networking.IPLookup.Static do
  @moduledoc """
  Module provides static IP address of the current node
  fetched from ENV variable or compile-time configuration.
  """
  
  # Public

  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, :invalid_ip_provider | :not_recognizable_ip}
  def get_node_ip do
    with config <- Application.get_env(:uniris, Uniris.Networking),
    {:ok, hostname} when is_binary(hostname) <- Keyword.fetch(config, :hostname),
    host_chars <- String.to_charlist(hostname),
    {:ok, ip} <- :inet.parse_address(host_chars) do
      {:ok, ip}
    else
      :error -> {:error, :invalid_ip_provider} 
      {:error, :einval} -> {:error, :not_recognizable_ip}
    end
  end
end