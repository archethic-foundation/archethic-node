defmodule Uniris.P2P.Transport.TCPImpl do
  @moduledoc false

  alias Uniris.P2P.TransportImpl

  @behaviour TransportImpl

  @nb_acceptors 10

  @server_options [
    :binary,
    {:packet, 4},
    {:active, false},
    {:reuseaddr, true},
    {:backlog, 500}
  ]

  @client_options [:binary, packet: 4, active: false]

  require Logger

  @impl TransportImpl
  def listen(port, handle_new_socket_fun) do
    {:ok, listen_socket} = :gen_tcp.listen(port, @server_options)

    Enum.each(1..@nb_acceptors, fn _ ->
      Task.start_link(fn -> accept_loop(listen_socket, handle_new_socket_fun) end)
    end)

    {:ok, listen_socket}
  end

  defp accept_loop(listen_socket, handle_new_socket_fun) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        handle_new_socket_fun.(socket)
        accept_loop(listen_socket, handle_new_socket_fun)

      {:error, reason} ->
        Logger.info("Connection failed: #{reason}")
    end
  end

  @impl TransportImpl
  def connect(ip, port, timeout),
    do: :gen_tcp.connect(ip, port, @client_options, timeout)

  @impl TransportImpl
  def send_message(socket, message), do: :gen_tcp.send(socket, message)

  @impl TransportImpl
  def read_from_socket(socket, size \\ 0, timeout \\ :infinity) do
    :gen_tcp.recv(socket, size, timeout)
  end
end
