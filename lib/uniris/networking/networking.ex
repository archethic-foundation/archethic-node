defmodule Uniris.Networking do
  @moduledoc """
  Module defines networking configuration of the node.
  """

  alias __MODULE__.{
    Config, IPLookup
  }

  # Public
  
  @doc """
  Provides current host IP address.
  """
  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, binary}
  defdelegate get_node_ip, to: IPLookup

  @doc """
  Provides P2P port number.
  """
  @spec get_p2p_port() :: {:ok, pos_integer} | {:error, binary}
  def get_p2p_port do
    Config.load_from_sys_env?
    |> case do
      {:error, reason} -> {:error, reason}
      {:ok, false} -> Config.p2p_port_from_config()
      {:ok, true} -> Config.p2p_port_from_env()
    end
  end
end