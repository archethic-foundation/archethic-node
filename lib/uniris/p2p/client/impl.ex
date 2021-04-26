defmodule Uniris.P2P.ClientImpl do
  @moduledoc false

  alias Uniris.Crypto

  alias Uniris.P2P.Message
  alias Uniris.P2P.Node
  alias Uniris.P2P.Transport

  @callback new_connection(
              :inet.ip_address(),
              port :: :inet.port_number(),
              Transport.supported(),
              Crypto.key()
            ) :: {:ok, pid()}

  @callback send_message(Node.t(), Message.request()) ::
              {:ok, Message.response()} | {:error, :network_issue}
end
