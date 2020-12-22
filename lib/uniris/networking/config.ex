defmodule Uniris.Networking.Config do
  @moduledoc """
  Module provides configuration assets for Networking module.
  """

  # Constants

  @env_p2p_port "UNIRIS_P2P_PORT"

  @error_sys_config "No system config found"
  @error_p2p_port_invalid "P2P port is invalid. Must be an uint"
  @error_p2p_port_env_missed "#{@env_p2p_port} env var is mandatory"
  @error_p2p_port_env_wrong "#{@env_p2p_port} env var is wrong"

  # Public

  @doc """
  :load_from_system_env config parameter is optional.
  Parameter absence treats as false
  """
  @spec load_from_sys_env?() :: {:ok, keyword()} | {:error, binary}
  def load_from_sys_env? do
    with {:ok, config} <- fetch() do
      config
      |> Keyword.fetch(:load_from_system_env)
      |> case do
        {:ok, true} -> {:ok, true}
        :error -> {:ok, false}
        {:ok, false} -> {:ok, false}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec p2p_port_from_config() :: {:ok, pos_integer} | {:error, binary}
  def p2p_port_from_config do
    with {:ok, config} <- fetch(),
    {:ok, port} when is_integer(port) <- Keyword.fetch(config, :port) do
      {:ok, port}
    else
      :error -> {:error, @error_p2p_port_invalid} 
      {:ok, _not_integer} -> {:error, @error_p2p_port_invalid} 
    end
  end

  @spec p2p_port_from_env() :: {:ok, pos_integer} | {:error, binary}
  def p2p_port_from_env do
    with env_port when not is_nil(env_port) <- System.get_env(@env_p2p_port),
    {port, ""} <- Integer.parse(env_port) do
      {:ok, port}
    else
      nil -> {:error, @error_p2p_port_env_missed}
      :error -> {:error, @error_p2p_port_env_wrong}
    end
  end

  # Private

  @spec fetch() :: {:ok, keyword()} | {:error, binary}
  defp fetch do
    case Application.get_env(:uniris, Uniris.Networking) do
      nil -> {:error, @error_sys_config}
      config -> {:ok, config}
    end
  end
end