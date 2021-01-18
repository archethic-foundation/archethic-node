defmodule Uniris.Networking.IPLookup.Nat do
  @moduledoc false
  
  # Public

  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, :ip_discovery_error}
  def get_node_ip do
    [:natupnp_v1, :natupnp_v2, :natpmp]
    |> discover
  end

  @spec get_random_port() :: {:ok, pos_integer} | {:error, any()}
  def get_random_port do
    [:natupnp_v1, :natupnp_v2, :natpmp]
    |> assign_port(0)
  end

  @spec open_port(pos_integer) :: {:ok, pos_integer} | {:error, any()}
  def open_port(port) do
    [:natupnp_v1, :natupnp_v2, :natpmp]
    |> assign_port(port)
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

  @spec assign_port(list(atom), pos_integer) :: {:ok, pos_integer} | {:error, any()}
  defp assign_port([], _port), do: {:error, :port_unassigned}
  defp assign_port([protocol_module | protocol_modules], port) do
    with {:ok, router_ip} <- protocol_module.discover(),
    {:ok, _since, internal_port, _external_port, _} <- protocol_module.add_port_mapping(router_ip, :tcp, port, port, 0) do
      {:ok, internal_port}
    else
      {:error, {:http_error, _code, _reason}} -> discover(protocol_modules)
      {:error, :einval} -> discover(protocol_modules)
      {:error, :no_nat} -> discover(protocol_modules)
      {:error, :timeout} -> discover(protocol_modules)
      {:error, reason} -> {:error, reason}
    end
  end
end