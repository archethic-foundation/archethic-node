defmodule Uniris.P2P.Transport.TCPImpl do
  @moduledoc false

  alias Uniris.P2P.TransportImpl

  @behaviour TransportImpl

  @impl TransportImpl
  def listen(port, options), do: :gen_tcp.listen(port, options)

  @impl TransportImpl
  def accept(listen_socket), do: :gen_tcp.accept(listen_socket)

  @impl TransportImpl
  def connect(ip, port, options, timeout), do: :gen_tcp.connect(ip, port, options, timeout)

  @impl TransportImpl
  def send_message(socket, message), do: :gen_tcp.send(socket, message)

  @impl TransportImpl
  def read_from_socket(socket, size, timeout), do: :gen_tcp.recv(socket, size, timeout)
end
