defmodule Uniris.P2P.Client.DefaultImpl do
  @moduledoc false

  use Retry

  alias Uniris.Crypto

  alias Uniris.P2P.Client.RemoteConnection
  alias Uniris.P2P.ClientImpl
  alias Uniris.P2P.Connection
  alias Uniris.P2P.ConnectionRegistry
  alias Uniris.P2P.ConnectionSupervisor
  alias Uniris.P2P.Node
  alias Uniris.P2P.Transport

  alias Retry.DelayStreams

  @behaviour ClientImpl

  @doc """
  Create a new node client connection for a remote node
  """
  @impl ClientImpl
  @spec new_connection(
          :inet.ip_address(),
          port :: :inet.port_number(),
          Transport.supported(),
          Crypto.key()
        ) :: {:ok, pid()}
  def new_connection(ip, port, transport, node_public_key) do
    DynamicSupervisor.start_child(
      ConnectionSupervisor,
      {RemoteConnection,
       ip: ip, port: port, transport: transport, node_public_key: node_public_key}
    )
  end

  @doc """
  Send a message to the given node using the right connection bearer
  """
  @impl ClientImpl
  def send_message(%Node{first_public_key: first_public_key}, message) do
    if first_public_key == Crypto.node_public_key(0) do
      LocalConnection
      |> Process.whereis()
      |> Connection.send_message(message)
    else
      retry_while with: DelayStreams.linear_backoff(10, 2) |> DelayStreams.expiry(100) do
        case Registry.lookup(ConnectionRegistry, {:bearer_conn, first_public_key}) do
          [{pid, _}] ->
            {:halt, Connection.send_message(pid, message)}

          [] ->
            {:cont, :not_found}
        end
      end
    end
  end
end
