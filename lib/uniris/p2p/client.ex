defmodule Uniris.P2P.Client do
  @moduledoc false

  @behaviour Uniris.P2P.ClientImpl
  alias Uniris.P2P.Message

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
    :uniris
    |> Application.get_env(Uniris.P2P)
    |> Keyword.fetch!(:node_client)
  end
end
