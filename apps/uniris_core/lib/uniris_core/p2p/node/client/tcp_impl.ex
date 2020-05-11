defmodule UnirisCore.P2P.NodeTCPClient do
  @moduledoc false

  @behaviour UnirisCore.P2P.NodeClientImpl

  @tcp_options [:binary, packet: 4, active: false]

  @impl true
  @spec send_message(ip :: :inet.ip_address(), port :: :inet.port_number(), message :: term()) ::
          result :: term()
  def send_message(ip, port, msg) do
    message = :erlang.term_to_binary(msg)

    with {:ok, socket} <- :gen_tcp.connect(ip, port, @tcp_options),
         :ok <- :gen_tcp.send(socket, message),
         {:ok, data} <- :gen_tcp.recv(socket, 0),
         :ok <- :gen_tcp.close(socket) do
      :erlang.binary_to_term(data)
    end
  end
end
