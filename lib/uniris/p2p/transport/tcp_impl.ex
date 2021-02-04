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
        {:ok, pid} =
          Task.Supervisor.start_child(ConnectionSupervisor, fn -> recv_loop(socket) end)

        :gen_tcp.controlling_process(listen_socket, pid)

      {:error, reason} ->
        Logger.info("TCP Connection failed: #{reason}")
    end

    accept(listen_socket)
  end

  defp recv_loop(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        encoded_result =
          data
          |> Message.decode()
          |> Message.process()
          |> Message.encode()
          |> Utils.wrap_binary()

        case :gen_tcp.send(socket, encoded_result) do
          :ok ->
            :gen_tcp.shutdown(socket, :write)

          {:error, :closed} ->
            Logger.info("TCP connection closed")

          {:error, reason} ->
            Logger.error("TCP error during sending data - #{reason}")

            :gen_tcp.shutdown(socket, :write)
        end

      {:error, :closed} ->
        Logger.info("TCP connection closed")

      {:error, reason} ->
        Logger.error("TCP error during receiving data - #{reason}")
        :gen_tcp.shutdown(socket, :read_write)
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

    with {:connection, {:ok, socket}} <-
           {:connection, :gen_tcp.connect(ip, port, @client_options, 3_000)},
         {:send, :ok} <- {:send, :gen_tcp.send(socket, encoded_message)},
         {:recv, {:ok, data}} <- {:recv, :gen_tcp.recv(socket, 0, 3_000)} do
      {:ok, Message.decode(data)}
    else
      {:connection, {:error, reason} = e} ->
        Logger.error("Connection failed #{:inet.ntoa(ip)} - #{inspect(reason)}")
        e

      {:send, {:error, reason} = e} ->
        Logger.error("Sending failed #{:inet.ntoa(ip)} - #{inspect(reason)}")
        e

      {:recv, {:error, reason} = e} ->
        Logger.error("Receiving failed with #{:inet.ntoa(ip)} - #{inspect(reason)}")
        e
    end
  end
end
