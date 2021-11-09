defmodule ArchEthic.P2P.Client.DefaultImpl do
  @moduledoc false

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Client
  alias ArchEthic.P2P.Client.Connection
  alias ArchEthic.P2P.Client.ConnectionSupervisor
  alias ArchEthic.P2P.Client.Transport.TCPImpl
  alias ArchEthic.P2P.Message
  alias ArchEthic.P2P.Node

  require Logger

  @behaviour Client

  @doc """
  Create a new node client connection for a remote node
  """
  @impl Client
  @spec new_connection(
          :inet.ip_address(),
          port :: :inet.port_number(),
          P2P.supported_transport(),
          Crypto.key()
        ) :: Supervisor.on_start()
  def new_connection(ip, port, transport, node_public_key) do
    ConnectionSupervisor.add_connection(
      transport: transport_mod(transport),
      ip: ip,
      port: port,
      node_public_key: node_public_key
    )
  end

  defp transport_mod(:tcp), do: TCPImpl
  defp transport_mod(other), do: other

  @doc """
  Send a message to the given node using the right connection bearer
  """
  @impl Client
  def send_message(
        %Node{first_public_key: node_public_key},
        message,
        timeout
      ) do
    if node_public_key == Crypto.first_node_public_key() do
      {:ok, Message.process(message)}
    else
      case Connection.send_message(node_public_key, message, timeout) do
        {:ok, data} ->
          {:ok, data}

        {:error, reason} ->
          Logger.warning("Cannot send message #{inspect(message)} - #{inspect(reason)}",
            node: Base.encode16(node_public_key)
          )

          {:error, reason}
      end
    end
  end
end
