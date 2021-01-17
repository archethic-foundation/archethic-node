defmodule Uniris.Networking.IPLookup.Nat do
  @moduledoc false
  
  # Public

  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, :ip_discovery_error}
  def get_node_ip do
    [:natupnp_v1, :natupnp_v2, :natpmp]
    |> discover
  end

  @spec assign_port(list(atom)) :: {:ok, pos_integer} | {:error, any()}
  def get_random_port do
    [:natupnp_v1, :natupnp_v2, :natpmp]
    |> assign_port
  end

  # Private

  @spec discover(list(atom)) :: {:ok, :inet.ip_address()} | {:error, :ip_discovery_error}
  defp discover([]), do: {:error, :ip_discovery_error}
  defp discover([protocol_module | protocol_modules]) do
    with {:ok, router_ip} <- protocol_module.discover(),
    {:ok, ip_chars} <- protocol_module.get_external_address(router_ip),
    {:ok, ip} <- :inet.parse_address(ip_chars) do
      {:ok, ip}
    else
      {:error, :einval} -> discover(protocol_modules)
      {:error, :no_nat} -> discover(protocol_modules)
      {:error, :timeout} -> discover(protocol_modules)
    end
  end

  @spec assign_port(list(atom)) :: {:ok, pos_integer} | {:error, any()}
  defp assign_port([]), do: {:error, :port_unassigned}
  defp assign_port([protocol_module | protocol_modules]) do
    with {:ok, router_ip} <- protocol_module.discover(),
    {:ok, _since, port, _external_port, _} <- protocol_module.add_port_mapping(router_ip, :tcp, 0, 0, 0) do
      {:ok, port}
    else
      {:error, :einval} -> discover(protocol_modules)
      {:error, :no_nat} -> discover(protocol_modules)
      {:error, :timeout} -> discover(protocol_modules)
      {:error, reason} -> {:error, reason}
    end
  end
end