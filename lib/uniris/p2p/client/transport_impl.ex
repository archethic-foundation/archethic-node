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
  def send_message(node = %Node{first_public_key: first_public_key}, message, timeout \\ 3_000) do
    if first_public_key == Crypto.node_public_key(0) do
      {:ok, Message.process(message)}
    else
      do_send_remotely(node, message, timeout)
    end
  end

  defp do_send_remotely(
         %Node{first_public_key: first_public_key},
         message,
         timeout
       ) do
    encoded_message =
      message
      |> Message.encode()
      |> Utils.wrap_binary()

    case ClientConnection.send_message(first_public_key, encoded_message, timeout) do
      {:ok, data} ->
        MemTable.increase_node_availability(first_public_key)
        {data, _} = Message.decode(data)
        {:ok, data}

      {:error, reason} ->
        :ok = MemTable.decrease_node_availability(first_public_key)
        {:error, reason}
    end
  end
end
