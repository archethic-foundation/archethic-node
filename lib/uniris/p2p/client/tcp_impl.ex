defmodule Uniris.P2P.TCPClient do
  @moduledoc false

  @behaviour Uniris.P2P.ClientImpl
  alias Uniris.P2P.Message

  @tcp_options [:binary, packet: 4, active: false]

  @impl true
  @spec send_message(
          ip :: :inet.ip_address(),
          port :: :inet.port_number(),
          message :: Message.t()
        ) ::
          {:ok, result :: Message.t()} | {:error, :network_issue}
  def send_message(ip, port, msg) do
    encoded_msg =
      msg
      |> Message.encode()
      |> Message.wrap_binary()

    with {:ok, socket} <- :gen_tcp.connect(ip, port, @tcp_options),
         :ok <- :gen_tcp.send(socket, encoded_msg),
         {:ok, data} <- :gen_tcp.recv(socket, 0),
         :ok <- :gen_tcp.close(socket) do
      {:ok, Message.decode(data)}
    else
      {:error, _} ->
        {:error, :network_issue}
    end
  end
end
