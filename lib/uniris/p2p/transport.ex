defmodule Uniris.P2P.Transport do
  @moduledoc false

  alias Uniris.P2P.Message
  alias Uniris.P2P.Transport.TCPImpl

  @type supported :: :tcp

  @doc """
  Open a connection to the given port
  """
  @spec listen(transport :: supported(), :inet.port_number()) ::
          {:ok, :inet.socket()} | {:error, reason :: :system_limit | :inet.posix()}
  def listen(:tcp, port), do: TCPImpl.listen(port)
  def listen(_, port), do: config_impl().listen(port)

  @doc """
  Accept an incoming connection request on a listening socket and delay processing to the function
  """
  @spec accept(
          transport :: supported(),
          socket :: :inet.socket()
        ) :: :ok
  def accept(:tcp, listen_socket),
    do: TCPImpl.accept(listen_socket)

  def accept(_, listen_socket),
    do: config_impl().accept(listen_socket)

  @doc """
  Send a message to a remote endpoint
  """
  @spec send_message(
          transport :: supported(),
          ip :: :inet.ip_address(),
          port :: :inet.port_number(),
          request_message :: Message.t()
        ) ::
          {:ok, response_message :: Message.t()} | {:error, reason :: :timeout | :inet.posix()}
  def send_message(transport, ip, port, request_message) do
    case do_send_message(transport, ip, port, request_message) do
      {:ok, response_message} ->
        {:ok, response_message}

      {:error, _} = e ->
        e
    end
  end

  defp do_send_message(:tcp, ip, port, message), do: TCPImpl.send_message(ip, port, message)
  defp do_send_message(_, ip, port, message), do: config_impl().send_message(ip, port, message)

  defp config_impl do
    Application.get_env(:uniris, __MODULE__)[:impl]
  end
end
