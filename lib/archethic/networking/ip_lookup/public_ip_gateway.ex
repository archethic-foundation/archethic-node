defmodule Archethic.Networking.IPLookup.PublicIPGateway do
  @moduledoc false

  def get_public_ip() do
    provider = get_public_ip_provider()
    provider.get_node_ip()
  end

  def get_public_ip_provider() do
    :archethic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:provider)
  end
end
