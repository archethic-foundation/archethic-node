defmodule Archethic.Networking.IPLookup.RemoteDiscovery do
  @moduledoc false
  # Module purpose:
  # Redirect the call
  # Mocktest feasiblity
  alias Archethic.Networking.IPLookup.RemoteDiscovery.Handler

  def get_node_ip() do
    remote_handler = module_args()
    remote_handler.get_node_ip()
  end

  defp module_args() do
    :archethic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:handler, Handler)
  end
end
