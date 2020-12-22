defmodule Uniris.Networking.IPLookup.Config do
  @moduledoc """
  Module provides configuration assets for IP Lookup module.
  """

  # Constants

  @env_hostname "HOSTNAME"

  @error_sys_config "No system config found"
  @error_ip_provider_invalid "IP provider is invalid"
  @error_hostname_invalid "Hostname is invalid"
  @error_hostname_env_missed "#{@env_hostname} env var is mandatory"

  # Public

  @doc """
  :load_from_system_env config parameter is optional.
  Parameter absence treats as false
  """
  @spec load_from_sys_env?() :: {:ok, keyword()} | {:error, binary}
  def load_from_sys_env? do
    with {:ok, config} <- fetch() do
      Keyword.fetch(config, :load_from_system_env)
      |> case do
        {:ok, true} -> {:ok, true}
        :error -> {:ok, false}
        {:ok, false} -> {:ok, false}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec ip_provider() :: {:ok, module} | {:error, binary}
  def ip_provider do
    with {:ok, config} <- fetch(),
    {:ok, ip_provider} <- Keyword.fetch(config, :ip_provider) do
      {:ok, ip_provider}
    else
      :error -> {:error, @error_ip_provider_invalid} 
      {:error, binary} -> {:error, binary}
    end
  end

  @spec hostname_from_config() :: {:ok, binary} | {:error, binary}
  def hostname_from_config do
    with {:ok, config} <- fetch(),
    {:ok, hostname} when is_binary(hostname) <- Keyword.fetch(config, :hostname) do
      {:ok, hostname}
    else
      :error -> {:error, @error_hostname_invalid} 
    end
  end

  @spec hostname_from_env() :: {:ok, binary} | {:error, binary}
  def hostname_from_env do
    with hostname when not is_nil(hostname) <- System.get_env(@env_hostname) do
      {:ok, hostname}
    else
      nil -> {:error, @error_hostname_env_missed}
      :error -> {:error, @error_hostname_invalid}
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