defmodule UnirisP2P.DefaultImpl.SupervisedConnection.Client.Impl do
  @moduledoc false

  @callback start_link(
              ip :: :inet.ip_address(),
              port :: :inet.port_number(),
              parent :: pid()
            ) ::
              {:ok, pid()}

  @callback send_message(client_pid :: pid(), message: term()) :: term()
end
