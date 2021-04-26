defmodule Uniris.P2P.Client.RemoteConnection do
  @moduledoc """
  Represents a client connection holder for a remote node
  """

  use Retry
  use GenServer

  alias Retry.DelayStreams

  alias Uniris.Crypto

  alias Uniris.P2P.Connection
  alias Uniris.P2P.ConnectionRegistry
  alias Uniris.P2P.Transport

  require Logger

  @type params :: [
          ip: :inet.ip_address(),
          port: :inet.port_number(),
          transport: Transport.supported(),
          node_public_key: Crypto.key()
        ]

  @doc """
  Create a new client connection for the remote node with the given transport
  """
  @spec start_link(params()) :: {:ok, pid()}
  def start_link(args \\ []) do
    node_public_key = Keyword.fetch!(args, :node_public_key)

    GenServer.start_link(__MODULE__, args,
      name: {:via, Registry, {ConnectionRegistry, {:remote_conn, node_public_key}}}
    )
  end

  def init(args) do
    ip = Keyword.fetch!(args, :ip)
    port = Keyword.fetch!(args, :port)
    transport = Keyword.fetch!(args, :transport)
    node_public_key = Keyword.fetch!(args, :node_public_key)

    {:ok, %{ip: ip, port: port, transport: transport, node_public_key: node_public_key},
     {:continue, :connect}}
  end

  def handle_continue(
        :connect,
        state = %{ip: ip, port: port, transport: transport, node_public_key: node_public_key}
      ) do
    new_state = Map.merge(state, do_connect(transport, ip, port, node_public_key))
    {:noreply, new_state}
  end

  defp do_connect(transport, ip, port, node_public_key) do
    retry_while with:
                  DelayStreams.exponential_backoff()
                  |> DelayStreams.randomize()
                  |> DelayStreams.cap(1_000) do
      case Transport.connect(transport, ip, port) do
        {:ok, socket} ->
          {:ok, connection_pid} =
            Connection.start_link(
              socket: socket,
              transport: transport,
              initiator?: true,
              name: {:via, Registry, {ConnectionRegistry, {:bearer_conn, node_public_key}}}
            )

          Logger.info("Connection established with #{:inet.ntoa(ip)}:#{port}",
            node: Base.encode16(node_public_key)
          )

          {:halt, %{socket: socket, connection_pid: connection_pid}}

        {:error, reason} ->
          Logger.warning(
            "Error during node connection #{inspect(reason)} to #{:inet.ntoa(ip)}:#{port}"
          )

          {:cont, reason}
      end
    end
  end
end
