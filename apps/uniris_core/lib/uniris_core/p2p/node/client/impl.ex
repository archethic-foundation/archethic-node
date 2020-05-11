defmodule UnirisCore.P2P.NodeClientImpl do
  @moduledoc false

  @callback send_message(ip :: :inet.ip_address(), port :: :inet.port_number(), message :: term()) ::
              result :: term()
end
