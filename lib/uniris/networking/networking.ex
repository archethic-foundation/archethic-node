defmodule Uniris.Networking do
  @moduledoc """
  Module defines networking configuration of the node.
  """

  alias __MODULE__.{Config, IPLookup}

  # Public
  
  @doc """
  Provides current host IP address.
  1. Provider is defined in config - Static -> use hostname from config
  2. Provider is defined in config - IPIFY -> use IPIFY
  3a. Provider is defined in config - NAT -> use NAT.
  3b. Provider is not defined in config -> use NAT.
  4. NAT discovery failed -> use IPIFY.
  5. IPIFY discovery failed -> return error :not_recognizable_ip.
  """
  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, :invalid_ip_provider | :not_recognizable_ip | :ip_discovery_error}
  def get_node_ip do
    with config when not is_nil(config) <- Application.get_env(:uniris, Uniris.Networking),
    {:ok, ip_provider} <- Keyword.fetch(config, :ip_provider) do
      ip_provider.get_node_ip()
    else
      :error -> get_external_ip() # Provider is not defined in config
    end
  end

  @doc """
  Provides P2P port number.
  Algo:
  1. Port in config && UPnP or NAT PMP is available - try to publish port from config.
  2. Port in config && Unable to publish port from config && UPnP or NAT PMP is available - get random port from the pool.
  3. Port in config && UPnP or NAT PMP not available -> return error :port_unassigned.
  """
  @spec get_p2p_port() :: {:ok, pos_integer} | {:error, :invalid_port | :port_unassigned}
  def get_p2p_port do
    with {:ok, port_to_open} <- Config.get_p2p_port,
    {:ok, port} <- IPLookup.Nat.open_port(port_to_open) do
      {:ok, port}
    else
      {:error, :invalid_port} -> {:error, :invalid_port} 
      {:error, :ip_discovery_error} -> 
        IPLookup.Nat.get_random_port
        |> case do
          {:ok, port} -> {:ok, port}
          {:error, _reason} -> {:error, :port_unassigned}
        end
    end
  end

  # Private

  @spec get_external_ip() :: {:ok, :inet.ip_address()} | {:error, :invalid_ip_provider | :not_recognizable_ip | :ip_discovery_error}
  defp get_external_ip do
    with {:ok, ip} <- IPLookup.Nat.get_node_ip do
      {:ok, ip}
    else
      {:error, _} -> IPLookup.Ipify.get_node_ip()
    end
  end
end