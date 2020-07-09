defmodule UnirisCore.P2P.NodeClient do
  @moduledoc false

  @behaviour UnirisCore.P2P.NodeClientImpl
  alias UnirisCore.P2P.Message

  @impl true
  @spec send_message(
          ip :: :inet.ip_address(),
          port :: :inet.port_number(),
          message :: Message.t()
        ) ::
          result :: Message.t()
  def send_message(ip, port, message) do
    impl().send_message(ip, port, message)
  end

  defp impl do
    :uniris_core
    |> Application.get_env(UnirisCore.P2P)
    |> Keyword.fetch!(:node_client)
  end
end
