defmodule Archethic.Networking.IPLookup.NATDiscovery do
  @moduledoc false
  # Module purpose:
  # redirect the call
  # ensures mocktest feasibility
  alias Archethic.Networking.IPLookup.NATDiscovery.Handler

  def get_node_ip() do
    local_handler = module_args()
    local_handler.get_node_ip()
  end

  defp module_args() do
    :archethic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:handler, Handler)
  end
end
