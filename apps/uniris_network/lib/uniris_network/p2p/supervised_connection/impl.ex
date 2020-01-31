defmodule UnirisNetwork.P2P.SupervisedConnection.Impl do
  @moduledoc false

  @callback start_link(
              public_key :: binary(),
              ip :: :inet.ip_address(),
              port :: :inet.port_number()
            ) :: {:ok, pid()}
  @callback send_message(connection :: pid(), message :: binary()) :: :ok
end
