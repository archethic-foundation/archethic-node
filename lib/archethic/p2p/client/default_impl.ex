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

  alias Archethic.BeaconChain.Update, as: BeaconUpdate

  require Logger

  @behaviour Client

  @doc """
  Create a new node client connection for a remote node
  """
  @impl Client
  @spec new_connection(
          ip :: :inet.ip_address(),
          port :: :inet.port_number(),
          transport :: P2P.supported_transport(),
          node_first_public_key :: Crypto.key(),
          from :: pid() | nil
        ) :: Supervisor.on_start()
  def new_connection(ip, port, transport, node_public_key, from) do
    case ConnectionSupervisor.add_connection(
           transport: transport_mod(transport),
           ip: ip,
           port: port,
           node_public_key: node_public_key,
           from: from
         ) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        # restart the connection if informations are updated
        {_state, current_conn} = :sys.get_state(pid)

        with false <- connected?(node_public_key),
             true <- informations_changed?(ip, port, transport, current_conn) do
          ConnectionSupervisor.cancel_connection(pid)
          new_connection(ip, port, transport, node_public_key, from)
        else
          _ ->
            {:ok, pid}
        end
    end
  end

  defp informations_changed?(ip, port, transport, %{
         ip: conn_ip,
         port: conn_port,
         transport: conn_transport
       }) do
    with true <- conn_ip == ip,
         true <- conn_port == port,
         true <- conn_transport == transport_mod(transport) do
      false
    else
      _ ->
        true
    end
  end

  defp transport_mod(:tcp), do: TCPImpl
  defp transport_mod(other), do: other

  @doc """
  Send a message to the given node using the right connection bearer
  """
  @spec send_message(
          node :: Node.t(),
          message :: Message.request(),
          options :: [
            timeout: timeout(),
            trace: binary()
          ]
        ) ::
          {:ok, Message.response()}
          | {:error, :timeout}
          | {:error, :closed}
  @impl Client
  def send_message(
        %Node{first_public_key: node_public_key},
        message,
        opts \\ []
      ) do
    if node_public_key == Crypto.first_node_public_key() do
      # if the node was itself just process the message
      {:ok,
       Message.process(message, %{
         sender_public_key: node_public_key,
         trace: Keyword.get(opts, :trace, "")
       })}
    else
      case Connection.send_message(node_public_key, message, opts) do
        {:ok, data} ->
          {:ok, data}

        {:error, reason} ->
          Logger.warning("Cannot send message #{inspect(message)} - #{inspect(reason)}",
            node: Base.encode16(node_public_key)
          )

          BeaconUpdate.unsubscribe(node_public_key)

          {:error, reason}
      end
    end
  end

  @impl Client
  defdelegate get_availability_timer(public_key, reset?), to: Connection

  @impl Client
  defdelegate connected?(public_key), to: Connection
end
