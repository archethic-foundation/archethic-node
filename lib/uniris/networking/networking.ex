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
  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, :invalid_ip_provider | :not_recognizable_ip}
  def get_node_ip do 
    IPLookup.get_node_ip
    |> case do
      {:ok, ip} ->
        :telemetry.execute([:uniris, :iplookup, :success], %{}, %{"ip" => "#{inspect ip}"})
        {:ok, ip}

      {:error, reason} ->
        :telemetry.execute([:uniris, :iplookup, :failure], %{}, %{"error" => "#{inspect reason}"})
        {:error, reason}
    end
  end

  @doc """
  Provides P2P port number.
  """
  @spec get_p2p_port() :: {:ok, pos_integer} | {:error, :invalid_port}
  defdelegate get_p2p_port, to: Config
end