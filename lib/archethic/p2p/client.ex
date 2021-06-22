defmodule ArchEthic.P2P.Client do
  @moduledoc false

  alias ArchEthic.Crypto

  alias __MODULE__.DefaultImpl

  alias ArchEthic.P2P.Message
  alias ArchEthic.P2P.Node
  alias ArchEthic.P2P.Transport

  use Knigge, otp_app: :archethic, default: DefaultImpl

  @callback new_connection(
              :inet.ip_address(),
              port :: :inet.port_number(),
              Transport.supported(),
              Crypto.key()
            ) :: {:ok, pid()}

  @callback send_message(Node.t(), Message.request()) ::
              {:ok, Message.response()} | {:error, :network_issue}
end
