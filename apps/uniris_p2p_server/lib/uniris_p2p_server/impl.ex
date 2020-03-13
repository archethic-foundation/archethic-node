defmodule UnirisP2PServer.Impl do
  @moduledoc false

  @callback start_link(port :: :inet.port_number()) :: {:ok, pid()}
end
