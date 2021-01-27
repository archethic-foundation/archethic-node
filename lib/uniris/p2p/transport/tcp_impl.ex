defmodule Uniris.P2P.Transport.TCPImpl do
  @moduledoc false

  @server_options [:binary, {:packet, 4}, {:active, false}, {:reuseaddr, true}, {:backlog, 500}]
  @client_options [:binary, packet: 4, active: false]

  alias Uniris.P2P.Endpoint.ConnectionSupervisor
  alias Uniris.P2P.Message
  alias Uniris.P2P.TransportImpl

  alias Uniris.Utils

  require Logger

  @behaviour TransportImpl

  @impl TransportImpl
  @spec listen(:inet.port_number()) ::
          {:ok, :inet.socket()} | {:error, reason :: :system_limit | :inet.posix()}
  def listen(port) do
    :gen_tcp.listen(port, @server_options)
  end

  @impl TransportImpl
  @spec accept(:inet.socket()) :: :ok
  def accept(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        Task.Supervisor.start_child(ConnectionSupervisor, fn -> recv_loop(socket) end)
        accept(listen_socket)

      {:error, reason} ->
        Logger.info("Connection failed: #{reason}")
    end
  end

  defp recv_loop(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        IO.puts "MESSAGE RECEIVED: #{inspect data}"
        encoded_result =
          data
          |> Message.decode()
          |> Message.process()
          |> Message.encode()
          |> Utils.wrap_binary()

        case :gen_tcp.send(socket, encoded_result) do
          :ok ->
            recv_loop(socket)

          {:error, :closed} ->
            Logger.info("TCP connection closed")

          {:error, reason} ->
            Logger.error("TCP error during sending data - #{reason}")
            recv_loop(socket)
        end

      {:error, :closed} ->
        :gen_tcp.close(socket)

      {:error, reason} ->
        Logger.error("TCP error during receiving data - #{reason}")
        :gen_tcp.close(socket)
    end
  end

  @impl TransportImpl
  @spec send_message(:inet.ip_address(), :inet.port_number(), request_message :: Message.t()) ::
          {:ok, response_message :: Message.t()} | {:error, reason :: :timeout | :inet.posix()}
  def send_message(ip, port, message) do
    encoded_message =
      message
      |> Message.encode()
      |> Utils.wrap_binary()

    case :gen_tcp.connect(ip, port, @client_options) do
      {:ok, socket} ->
        with :ok <- :gen_tcp.send(socket, encoded_message),
             {:ok, data} <- :gen_tcp.recv(socket, 0),
             :ok <- :gen_tcp.close(socket) do
          {:ok, Message.decode(data)}
        else
          {:error, _} = e ->
            :gen_tcp.close(socket)
            e
        end

      {:error, _} = e ->
        e
    end
  end
end
