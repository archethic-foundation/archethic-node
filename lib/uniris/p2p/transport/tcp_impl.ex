defmodule Uniris.P2P.Transport.TCPImpl do
  @moduledoc false

  alias Uniris.P2P.Endpoint.Listener
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
  def listen(port, _) do
    {:ok, listen_socket} = :gen_tcp.listen(port, @server_options)

    Enum.each(1..@nb_acceptors, fn _ ->
      Task.start_link(fn -> accept_loop(listen_socket) end)
    end)

    {:ok, listen_socket}
  end

  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        Listener.handle_new_connection(socket)
        accept_loop(listen_socket)

      {:error, reason} ->
        Logger.info("Connection failed: #{reason}")
    end
  end

  @impl TransportImpl
  def connect(ip, port, _options, timeout),
    do: :gen_tcp.connect(ip, port, @client_options, timeout)

  @impl TransportImpl
  def send_message(socket, message), do: :gen_tcp.send(socket, message)

  @impl TransportImpl
  def read_from_socket(socket, fun, size \\ 0, timeout \\ :infinity) do
    case :gen_tcp.recv(socket, size, timeout) do
      {:ok, data} ->
        Task.start(fn -> fun.(data) end)
        read_from_socket(socket, fun, size, timeout)

      {:error, :closed} = e ->
        Logger.debug("Connection closed")
        e

      {:error, reason} = e ->
        Logger.error("Read data error: #{reason}")
        e
    end
  end
end
