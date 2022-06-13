defmodule Archethic.Networking.IPLookup.NATDiscovery do
  @moduledoc """
  Provide implementation to discover ip address using NAT
  """

  alias Archethic.Networking.IPLookup.Impl

  @behaviour Impl
  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, any()}
  def get_node_ip do
    provider().get_node_ip()
  end

  @spec open_port(non_neg_integer()) :: :ok | :error
  def open_port(port) do
    provider().open_port(port)
  end

  defp provider do
    :archethic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:provider, __MODULE__.MiniUPNP)
  end
end
