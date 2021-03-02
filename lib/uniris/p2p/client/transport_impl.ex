defmodule Uniris.P2P.Client.TransportImpl do
  @moduledoc false

  alias Uniris.Crypto

  alias Uniris.P2P.ClientConnection
  alias Uniris.P2P.ClientImpl
  alias Uniris.P2P.MemTable
  alias Uniris.P2P.Message

  alias Uniris.P2P.Node

  alias Uniris.Utils

  @behaviour ClientImpl

  @impl ClientImpl
  def send_message(node = %Node{first_public_key: first_public_key}, message) do
    if first_public_key == Crypto.node_public_key(0) do
      Message.process(message)
    else
      do_send_remotely(node, message)
    end
  end

  defp do_send_remotely(
         %Node{first_public_key: first_public_key, ip: ip, port: port},
         message
       ) do
    encoded_message =
      message
      |> Message.encode()
      |> Utils.wrap_binary()

    case ClientConnection.send_message(first_public_key, encoded_message) do
      {:ok, data} ->
        MemTable.increase_node_availability(first_public_key)
        Message.decode(data)

      {:error, reason} ->
        :ok = MemTable.decrease_node_availability(first_public_key)
        raise "Messaging error with #{:inet.ntoa(ip)}:#{port} - reason: #{reason}"
    end
  end
end
