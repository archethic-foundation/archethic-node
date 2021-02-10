defmodule Uniris.Networking do
  @moduledoc """
  Module defines networking configuration of the node.
  """

  alias __MODULE__.IPLookup
  alias __MODULE__.PortForwarding

  @doc """
  Provides current host IP address by leveraging the IP lookup provider.

  If there is some problems from the provider, fallback methods are used to fetch the IP

  Otherwise error will be thrown
  """
  @spec get_node_ip() :: :inet.ip_address()
  defdelegate get_node_ip, to: IPLookup

  @doc """
  Try to open the port from the configuration. 

  If not possible try other random port. Otherwise assume the port is open

  A force parameter can be given to use a random port if the port publication doesn't work
  """
  @spec try_open_port(:inet.port_number(), boolean()) :: :inet.port_number()
  defdelegate try_open_port(port, force?), to: PortForwarding
end
