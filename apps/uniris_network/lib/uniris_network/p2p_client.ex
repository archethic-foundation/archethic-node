defmodule UnirisNetwork.P2PClient do
  @moduledoc false

  @callback start_link(
              ip :: :inet.ip_address(),
              port :: :inet.port_number(),
              public_key :: binary(),
              from :: pid()
            ) :: {:ok, pid()}

  @callback send_message(public_key :: binary(), message: term()) :: :ok
end
