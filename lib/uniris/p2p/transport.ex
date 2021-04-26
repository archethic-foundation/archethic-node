defmodule Uniris.P2P.Transport do
  @moduledoc false

  @type supported :: :tcp

  @doc """
  Return the list of supported transport implementation
  """
  @spec supported() :: list(supported())
  def supported, do: [:tcp]

  require Logger

  alias Uniris.P2P.Transport.TCPImpl

  @doc """
  Open a connection to the given port
  """
  @spec listen(
          transport :: supported(),
          port :: :inet.port_number(),
          (:inet.socket() -> {:ok, pid()})
        ) ::
          {:ok, :inet.socket()} | {:error, reason :: :system_limit | :inet.posix()}
  def listen(transport, port, handle_new_socket_fun) when port in 0..65_535,
    do: do_listen(transport, port, handle_new_socket_fun)

  defp do_listen(:tcp, port, handle_new_socket_fun),
    do: TCPImpl.listen(port, handle_new_socket_fun)

  defp do_listen(_, port, handle_new_socket_fun),
    do: config_impl().listen(port, handle_new_socket_fun)

  @doc """
  Establish a connection to a remote node
  """
  @spec connect(
          supported(),
          ip :: :inet.ip_address(),
          port :: :inet.port_number(),
          timeout :: timeout()
        ) :: {:ok, :inet.socket()} | {:error, :inet.posix()}
  def connect(transport, ip, port, timeout \\ :infinity)
      when port in 0..65_535 and
             (timeout == :infinity or (is_integer(timeout) and timeout >= 0)) do
    do_connect(transport, ip, port, timeout)
  end

  defp do_connect(:tcp, ip, port, timeout),
    do: TCPImpl.connect(ip, port, timeout)

  defp do_connect(_, ip, port, timeout),
    do: config_impl().connect(ip, port, timeout)

  @doc """
  Send a message through a socket
  """
  @spec send_message(supported(), socket :: :inet.socket(), message :: binary()) ::
          :ok | {:error, :inet.posix()}
  def send_message(:tcp, socket, message), do: TCPImpl.send_message(socket, message)
  def send_message(_, socket, message), do: config_impl().send_message(socket, message)

  @doc """
  Read data from a socket
  """
  @spec read_from_socket(
          supported(),
          :inet.socket(),
          size_to_read :: non_neg_integer(),
          timeout :: timeout()
        ) :: {:ok, binary()} | {:error, :inet.posix()}
  def read_from_socket(transport, socket, size \\ 0, timeout \\ :infinity)
      when is_integer(size) and size >= 0 and
             (timeout == :infinity or (is_integer(timeout) and timeout >= 0)) do
    do_read_from_socket(transport, socket, size, timeout)
  end

  defp do_read_from_socket(:tcp, socket, size, timeout),
    do: TCPImpl.read_from_socket(socket, size, timeout)

  defp do_read_from_socket(_, socket, size, timeout),
    do: config_impl().read_from_socket(socket, size, timeout)

  defp config_impl do
    Application.get_env(:uniris, __MODULE__)[:impl]
  end
end
