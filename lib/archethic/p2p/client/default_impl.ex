defmodule Archethic.P2P.Client.DefaultImpl do
  @moduledoc false

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Client
  alias Archethic.P2P.Client.Connection
  alias Archethic.P2P.Client.ConnectionSupervisor
  alias Archethic.P2P.Client.Transport.TCPImpl
  alias Archethic.P2P.Message
  alias Archethic.P2P.Node

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
      # if the node was itself just process the message
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
