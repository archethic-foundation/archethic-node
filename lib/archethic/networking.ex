defmodule Archethic.Networking do
  @moduledoc """
  Module defines networking configuration of the node.
  """

  alias __MODULE__.IPLookup
  alias __MODULE__.PortForwarding

  @ip_validate_regex ~r/(^0\.)|(^127\.)|(^10\.)|(^172\.1[6-9]\.)|(^172\.2[0-9]\.)|(^172\.3[0-1]\.)|(^192\.168\.)/

  @doc ~S"""
  Validates whether a given IP is a valid Public IP depending

  upon whether it should be validated or not?

  When mix_env = :dev , Use of Private IP : allowed , returns :ok
  Static and Subnet(NAT), Private IP not to be validated to be public IP.

  When mix_env = :prod, Use of Private IP : not allowed,
  IP must be validated for a valid Public IP, otherwise return error

  ## Example

      iex> Archethic.Networking.validate_ip({0, 0, 0, 0}, false)
      :ok

      iex> Archethic.Networking.validate_ip({127, 0, 0, 1}, true)
      {:error, :invalid_ip}


      iex> Archethic.Networking.validate_ip({54, 39, 186, 147}, true)
      :ok

  """
  @spec validate_ip(:inet.ip_address(), boolean()) :: :ok | {:error, :invalid_ip}
  def validate_ip(ip, ip_validation? \\ should_validate_node_ip?())
  def validate_ip(_ip, false), do: :ok

  def validate_ip(ip, true) do
    if valid_ip?(ip) do
      :ok
    else
      {:error, :invalid_ip}
    end
  end

  @doc """
  Provides current host IP address by leveraging the IP lookup provider.

  If there is some problems from the provider, fallback methods are used to fetch the IP

  Otherwise error will be returned
  """
  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, any()}
  defdelegate get_node_ip, to: IPLookup

  @doc """
  Try to open the port from the configuration.

  If not possible try other random port. Otherwise assume the port is open

  A force parameter can be given to use a random port if the port publication doesn't work
  """
  @spec try_open_port(:inet.port_number(), boolean()) :: {:ok, :inet.port_number()} | :error
  defdelegate try_open_port(port, force?), to: PortForwarding

  @doc ~S"""
  Filters private IP address ranges

  ## Example

      iex> Archethic.Networking.valid_ip?({0, 0, 0, 0})
      false

      iex> Archethic.Networking.valid_ip?({127, 0, 0, 1})
      false

      iex> Archethic.Networking.valid_ip?({192, 168, 1, 1})
      false

      iex> Archethic.Networking.valid_ip?({10, 10, 0, 1})
      false

      iex> Archethic.Networking.valid_ip?({172, 16, 0, 1})
      false

      iex> Archethic.Networking.valid_ip?({54, 39, 186, 147})
      true
  """
  @spec valid_ip?(:inet.ip_address()) :: boolean()
  def valid_ip?(ip) do
    case :inet.ntoa(ip) do
      {:error, :einval} ->
        false

      ip_str ->
        !Regex.match?(
          @ip_validate_regex,
          to_string(ip_str)
        )
    end
  end

  defp should_validate_node_ip?() do
    :archethic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:validate_node_ip, false)
  end
end
