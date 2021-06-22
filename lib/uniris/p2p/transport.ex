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

  @default_impl Application.compile_env(:uniris, __MODULE__)

  @doc """
  Open a connection to the given port
  """
  @spec listen(
          transport :: supported(),
          port :: :inet.port_number(),
          (:inet.socket() -> {:ok, pid()})
        ) ::
          {:ok, :inet.socket()} | {:error, reason :: :system_limit | :inet.posix()}
  def listen(transport, port, handle_new_socket_fun) when port in 0..65_535 do
    transport
    |> delegate_to
    |> apply(:listen, [port, handle_new_socket_fun])
  end

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
    transport
    |> delegate_to
    |> apply(:connect, [ip, port, timeout])
  end

  @doc """
  Send a message through a socket
  """
  @spec send_message(supported(), socket :: :inet.socket(), message :: binary()) ::
          :ok | {:error, :inet.posix()}
  def send_message(transport, socket, message) do
    transport
    |> delegate_to
    |> apply(:send_message, [socket, message])
  end

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
    transport
    |> delegate_to
    |> apply(:read_from_socket, [socket, size, timeout])
  end

  @doc """
  Close an opened socket
  """
  @spec close_socket(supported(), :inet.socket()) :: :ok
  def close_socket(transport, socket) do
    transport
    |> delegate_to()
    |> apply(:close_socket, [socket])
  end

  defp delegate_to(:tcp), do: TCPImpl
  defp delegate_to(_), do: @default_impl
end
