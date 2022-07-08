defmodule Archethic.P2P.Client do
  @moduledoc false

  alias Archethic.Crypto

  alias __MODULE__.DefaultImpl

  alias Archethic.P2P
  alias Archethic.P2P.Message
  alias Archethic.P2P.Node

  use Knigge, otp_app: :archethic, default: DefaultImpl

  @callback new_connection(
              :inet.ip_address(),
              port :: :inet.port_number(),
              P2P.supported_transport(),
              Crypto.key()
            ) :: Supervisor.on_start()

  @callback send_message(Node.t(), Message.request(), timeout()) ::
              {:ok, Message.response()}
              | {:error, :timeout}
              | {:error, :closed}

  @callback set_connected(Crypto.key()) :: :ok
end
