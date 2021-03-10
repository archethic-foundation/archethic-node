defmodule Uniris.P2P.ClientConnection do
  @moduledoc """
  Represents a client connection holder for a remote node
  """

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.ConnectionRegistry
  alias Uniris.P2P.Multiplexer
  alias Uniris.P2P.Transport

  use GenStateMachine, callback_mode: :handle_event_function

  require Logger

  @doc """
  Create a new connection worker for the remote node with the given transport
  """
  @spec start_link(
          ip: :inet.ip_address(),
          port: :inet.port_number(),
          node_public_key: Crypto.key()
        ) :: {:ok, pid()}
  def start_link(args \\ []) do
    node_public_key = Keyword.fetch!(args, :node_public_key)
    GenStateMachine.start_link(__MODULE__, args, name: via_tuple(node_public_key))
  end

  @doc """
  Send a message to the connected remote node
  """
  @spec send_message(
          pid() | Crypto.key(),
          binary(),
          timeout()
        ) ::
          {:ok, binary()} | {:error, :disconnected} | {:error, :network_issue}
  def send_message(pid_or_public_key, message, timeout \\ 3_000)

  def send_message(pid, message, timeout)
      when is_pid(pid) and is_binary(message) do
    GenStateMachine.call(pid, {:send_message, message, timeout})
  end

  def send_message(node_public_key, message, timeout)
      when is_binary(node_public_key) and is_binary(message) do
    GenStateMachine.call(via_tuple(node_public_key), {:send_message, message, timeout})
  end

  defp via_tuple(node_public_key) do
    {:via, Registry, {ConnectionRegistry, node_public_key}}
  end

  def init(args) do
    ip = Keyword.get(args, :ip)
    port = Keyword.get(args, :port)
    transport = Keyword.get(args, :transport)
    node_public_key = Keyword.get(args, :node_public_key)

    {:ok, :idle, %{ip: ip, port: port, transport: transport, node_public_key: node_public_key},
     [{:next_event, :info, :connect}]}
  end

  def handle_event(
        :info,
        :connect,
        _,
        data = %{ip: ip, port: port, transport: transport, node_public_key: node_public_key}
      ) do
    socket = do_connect(transport, ip, port)

    {:ok, multiplex_pid} =
      Multiplexer.start_link(
        socket: socket,
        transport: transport,
        recv_handler: &handle_responses/3
      )

    Logger.info("Connection established with #{:inet.ntoa(ip)}:#{port}",
      node: Base.encode16(node_public_key)
    )

    new_data =
      data
      |> Map.put(:socket, socket)
      |> Map.put(:multiplexer_pid, multiplex_pid)

    {:next_state, :connected, new_data}
  end

  def handle_event(
        {:call, from},
        {:send_message, message, timeout},
        :connected,
        _data = %{multiplexer_pid: multiplexer_pid, node_public_key: node_public_key}
      ) do
    Task.start(fn ->
      case Multiplexer.send_data(multiplexer_pid, message, timeout) do
        {:ok, data} ->
          GenStateMachine.reply(from, {:ok, data})

        {:error, :closed} ->
          send(self(), :reconnect)

          # TODO: remove when the beacon P2P availability notification will be implemented
          P2P.set_node_globally_unavailable(node_public_key)

          GenStateMachine.reply(from, {:error, :disconnected})

        {:error, :timeout} ->
          GenStateMachine.reply(from, {:error, :timeout})
      end
    end)

    :keep_state_and_data
  end

  defp do_connect(transport, ip, port, retries \\ 0) do
    case Transport.connect(transport, ip, port, timeout: 3_000) do
      {:ok, socket} ->
        socket

      {:error, reason} ->
        Logger.warn(
          "Error during node connection #{inspect(reason)} to #{:inet.ntoa(ip)}:#{port}"
        )

        Process.sleep(100 * (retries + 1))
        do_connect(transport, ip, port, retries + 1)
    end
  end

  defp handle_responses(id, data, opts) do
    multiplexer_pid = Keyword.get(opts, :multiplexer_pid)
    Multiplexer.notify_clients(multiplexer_pid, id, data)
  end
end
