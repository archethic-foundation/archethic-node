defmodule Uniris.Networking do
  @moduledoc """
  Module defines networking configuration of the node.
  """

  alias __MODULE__.{Config, IPLookup}

  # Public
  
  @doc """
  Provides current host IP address.
  1. No provider in config -> use NAT discovery.
  2. No provider in config && NAT discovery failed -> use IPIFY.
  3. No provider in config && NAT discovery failed && IPIFY failed (for any reason) -> use hostname from config.
  4. No provider in config && NAT discovery failed && IPIFY failed (for any reason) && no hostname in config -> use localhost.
  5. Provider in config -> use provider.
  6. Provider in config failed -> Goto 1.
  """
  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, :invalid_ip_provider | :not_recognizable_ip | :ip_discovery_error}
  defdelegate get_node_ip, to: IPLookup

  @doc """
  Provides P2P port number.
  Algo:
  1. No port in config && UPnP or NAT PMP is available -> get random port from the pool.
  2. Port in config && UPnP or NAT PMP is available - try to publish port from config.
  3. Port in config && Unable to publish port from config && UPnP or NAT PMP is available - get random port from the pool.
  4. Port in config && UPnP or NAT PMP not available -> return port from config.
  5. No port in config && UPnP or NAT PMP not available -> find open port.
  6. No port in config && open port not found && UPnP or NAT PMP not available -> return error.
  """
  @spec get_p2p_port() :: {:ok, pos_integer} | {:error, :invalid_port | :port_unassigned}
  def get_p2p_port do
    with {:error, _reason} <- IPLookup.Nat.get_random_port(),
    {:error, :invalid_port} <- Config.get_p2p_port do
      port = Enum.random(31000..33000)
      {:ok, port}
    else
      {:ok, port} -> {:ok, port}
    end
  end
end