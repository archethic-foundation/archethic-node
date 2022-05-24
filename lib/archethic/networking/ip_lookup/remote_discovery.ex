defmodule Archethic.Networking.IPLookup.RemoteDiscovery do
  @moduledoc """
  Provide abstraction over public ip provider
  """

  def get_node_ip() do
    get_provider().get_node_ip()
  end

  def get_provider() do
    :archethic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:provider)
  end
end
