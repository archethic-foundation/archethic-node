defmodule Archethic.P2P.Client do
  @moduledoc false

  alias Archethic.Crypto

  alias __MODULE__.DefaultImpl

  alias Archethic.P2P
  alias Archethic.P2P.Message
  alias Archethic.P2P.Node

  use Knigge, otp_app: :archethic, default: DefaultImpl

  @callback new_connection(
              ip :: :inet.ip_address(),
              port :: :inet.port_number(),
              transport :: P2P.supported_transport(),
              node_first_public_key :: Crypto.key(),
              from :: pid() | nil
            ) :: Supervisor.on_start()

  @callback send_message(
              node :: Node.t(),
              message :: Message.request(),
              opts :: [timeout: timeout(), trace: binary()]
            ) ::
              {:ok, Message.response()}
              | {:error, :timeout}
              | {:error, :closed}

  @callback get_availability_timer(Crypto.key(), boolean()) :: non_neg_integer()

  @callback connected?(Crypto.key()) :: boolean()
end
