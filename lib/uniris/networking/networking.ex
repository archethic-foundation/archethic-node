defmodule Uniris.Networking do
  @moduledoc """
  Module defines networking configuration of the node.
  """

  alias __MODULE__.{Config, IPLookup}

  # Public
  
  @doc """
  Provides current host IP address.
  """
  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, :invalid_ip_provider | :not_recognizable_ip | :ip_discovery_error}
  defdelegate get_node_ip, to: IPLookup

  @doc """
  Provides P2P port number.
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