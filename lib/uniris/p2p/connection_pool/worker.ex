defmodule Uniris.P2P.ConnectionPool.Worker do
  @moduledoc """
  Represents a connection worker to a remote node
  """

  @client_options [:binary, packet: 4, active: false]

  alias Uniris.P2P.Transport

  @behaviour :gen_statem

  require Logger

  @doc """
  Create a new connection worker for the remote node with the given transport
  """
  @spec start_link(
          ip: :inet.ip_address(),
          port: :inet.port_number(),
          transport: Transport.supported()
        ) :: {:ok, pid()}
  def start_link(args \\ []) do
    :gen_statem.start_link(__MODULE__, args, [])
  end

  @doc """
  Send a message to the connected remote node
  """
  @spec send_message(pid(), binary(), pos_integer()) ::
          {:ok, binary()} | {:error, :disconnected} | {:error, :network_issue}
  def send_message(pid, message, retries \\ 5)
      when is_pid(pid) and is_binary(message) and is_integer(retries) and retries >= 1 do
    :gen_statem.call(pid, {:send_message, message, retries})
  end

  def init(args) do
    Logger.debug("INIT")
    ip = Keyword.get(args, :ip)
    port = Keyword.get(args, :port)
    transport = Keyword.get(args, :transport)

    {:ok, :idle, %{ip: ip, port: port, transport: transport},
     [{:next_event, :internal, :connect}]}
  end

  def callback_mode, do: [:handle_event_function]

  def handle_event(:internal, :connect, _, data = %{ip: ip, port: port, transport: transport}) do
    socket = do_connect(transport, ip, port)
    Logger.info("Connection established with #{:inet.ntoa(ip)}:#{port}")
    {:next_state, :connected, Map.put(data, :socket, socket)}
  end

  def handle_event(
        {:call, from},
        {:send_message, message, retries},
        :connected,
        data = %{socket: socket, transport: transport}
      ) do
    case do_send_message(transport, socket, message, retries) do
      {:ok, data} ->
        {:keep_state_and_data, {:reply, from, {:ok, data}}}

      {:error, :disconnected} ->
        {:next_state, :disconnected, data,
         [{:reply, from, {:error, :disconnected}}, {:next_event, :internal, :connect}]}

      {:error, :network_issue} ->
        {:next_state, :disconnected, data,
         [{:reply, from, {:error, :network_issue}}, {:next_event, :internal, :connect}]}
    end
  end

  def handle_event({:call, _}, {:send_message, _}, _, _), do: {:keep_state_and_data, :postpone}

  defp do_connect(transport, ip, port, retries \\ 0) do
    case Transport.connect(transport, ip, port, @client_options, 3_000) do
      {:ok, socket} ->
        socket

      _ ->
        Process.sleep(100 * (retries + 1))
        do_connect(transport, ip, port, retries + 1)
    end
  end

  defp do_send_message(
         transport,
         socket,
         encoded_message,
         max_retries,
         timeout \\ 3_000,
         retries \\ 0
       )

  defp do_send_message(_transport, _socket, _encoded_message, max_retries, _timeout, retries)
       when retries == max_retries,
       do: {:error, :network_issue}

  defp do_send_message(transport, socket, encoded_message, max_retries, timeout, retries) do
    with :ok <- Transport.send_message(transport, socket, encoded_message),
         {:ok, data} <- Transport.read_from_socket(transport, socket, 0, timeout) do
      {:ok, data}
    else
      {:error, :timeout} ->
        Process.sleep(retries + 1 * 500)

        do_send_message(
          transport,
          socket,
          encoded_message,
          max_retries,
          timeout + (retries + 1 * 500),
          retries + 1
        )

      {:error, :closed} ->
        {:error, :disconnected}
    end
  end
end
