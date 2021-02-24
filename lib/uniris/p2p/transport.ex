defmodule Uniris.P2P.Transport do
  @moduledoc false

  @type supported :: :tcp

  require Logger

  alias Uniris.P2P.Transport.TCPImpl

  @doc """
  Open a connection to the given port
  """
  @spec listen(transport :: supported(), :inet.port_number(), options :: list()) ::
          {:ok, :inet.socket()} | {:error, reason :: :system_limit | :inet.posix()}
  def listen(transport, port, options \\ []) when port in 0..65_535 and is_list(options) do
    do_listen(transport, port, options)
  end

  defp do_listen(:tcp, port, options) do
    TCPImpl.listen(port, options)
  end

  defp do_listen(_, port, options), do: config_impl().listen(port, options)

  @doc """
  Establish a connection to a remote node
  """
  @spec connect(
          supported(),
          ip :: :inet.ip_address(),
          port :: :inet.port_number(),
          options :: list(),
          timeout :: timeout()
        ) :: {:ok, :inet.socket()} | {:error, :inet.posix()}
  def connect(transport, ip, port, options \\ [], timeout \\ :infinity)
      when port in 0..65_535 and is_list(options) and
             (timeout == :infinity or (is_integer(timeout) and timeout >= 0)) do
    do_connect(transport, ip, port, options, timeout)
  end

  defp do_connect(:tcp, ip, port, options, timeout),
    do: TCPImpl.connect(ip, port, options, timeout)

  defp do_connect(_, ip, port, options, timeout),
    do: config_impl().connect(ip, port, options, timeout)

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
          (binary() -> :ok),
          size_to_read :: non_neg_integer(),
          timeout :: timeout()
        ) :: {:ok, binary()} | {:error, :inet.posix()}
  def read_from_socket(transport, socket, fun, size \\ 0, timeout \\ :infinity)
      when is_function(fun) and is_integer(size) and size >= 0 and
             (timeout == :infinity or (is_integer(timeout) and timeout >= 0)) do
    do_read_from_socket(transport, socket, fun, size, timeout)
  end

  defp do_read_from_socket(:tcp, socket, fun, size, timeout),
    do: TCPImpl.read_from_socket(socket, fun, size, timeout)

  defp do_read_from_socket(_, socket, fun, size, timeout),
    do: config_impl().read_from_socket(socket, fun, size, timeout)

  defp config_impl do
    Application.get_env(:uniris, __MODULE__)[:impl]
  end
end
