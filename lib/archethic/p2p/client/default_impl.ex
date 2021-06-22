defmodule ArchEthic.P2P.Client.DefaultImpl do
  @moduledoc false

  use Retry

  alias ArchEthic.Crypto

  alias ArchEthic.P2P.Client
  alias ArchEthic.P2P.Client.RemoteConnection
  alias ArchEthic.P2P.Connection
  alias ArchEthic.P2P.ConnectionRegistry
  alias ArchEthic.P2P.ConnectionSupervisor
  alias ArchEthic.P2P.LocalConnection
  alias ArchEthic.P2P.Node
  alias ArchEthic.P2P.Transport

  @behaviour Client

  @doc """
  Create a new node client connection for a remote node
  """
  @impl Client
  @spec new_connection(
          :inet.ip_address(),
          port :: :inet.port_number(),
          Transport.supported(),
          Crypto.key()
        ) :: {:ok, pid()}
  def new_connection(ip, port, transport, node_public_key) do
    DynamicSupervisor.start_child(
      ConnectionSupervisor,
      %{
        id: {:remote_conn, node_public_key},
        start:
          {RemoteConnection, :start_link,
           [[ip: ip, port: port, node_public_key: node_public_key, transport: transport]]}
      }
    )
  end

  @doc """
  Send a message to the given node using the right connection bearer
  """
  @impl Client
  def send_message(%Node{first_public_key: first_public_key}, message) do
    if first_public_key == Crypto.first_node_public_key() do
      LocalConnection
      |> Process.whereis()
      |> Connection.send_message(message)
    else
      retry_while with: linear_backoff(10, 2) |> expiry(100) do
        case Registry.lookup(ConnectionRegistry, {:bearer_conn, first_public_key}) do
          [{pid, _}] ->
            try do
              {:halt, Connection.send_message(pid, message)}
            catch
              _ ->
                {:cont, {:error, :network_issue}}

              :exit, _ ->
                {:cont, {:error, :network_issue}}
            end

          [] ->
            {:cont, {:error, :network_issue}}
        end
      end
    end
  end
end
