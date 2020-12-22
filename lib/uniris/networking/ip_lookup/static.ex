defmodule Uniris.Networking.IPLookup.Static do
  @moduledoc """
  Module provides static IP address of the current node
  fetched from ENV variable or compile-time configuration.
  """

  alias Uniris.Networking.IPLookup.Config

  @error_invalid_ip "Invalid IP address"
  
  # Public

  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, binary}
  def get_node_ip do
    Config.load_from_sys_env?
    |> case do
      {:error, reason} -> {:error, reason}
      {:ok, false} -> Config.hostname_from_config()
      {:ok, true} -> Config.hostname_from_env()
    end
    |> case do
      {:error, reason} -> {:error, reason}
      {:ok, hostname} ->
        hostname
        |> String.to_charlist
        |> :inet.parse_address
        |> case do
          {:ok, ip} -> {:ok, ip}
          {:error, :einval} -> {:error, @error_invalid_ip}
        end
    end
  end
end