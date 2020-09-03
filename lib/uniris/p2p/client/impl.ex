defmodule Uniris.P2P.ClientImpl do
  @moduledoc false

  alias Uniris.P2P.Message

  @callback send_message(
              ip :: :inet.ip_address(),
              port :: :inet.port_number(),
              message :: Message.t()
            ) :: {:ok, result :: Message.t()} | {:error, :network_issue}
end
