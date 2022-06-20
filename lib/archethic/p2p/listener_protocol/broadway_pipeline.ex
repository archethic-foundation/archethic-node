defmodule Archethic.P2P.ListenerProtocol.BroadwayPipeline do
  @moduledoc false

  alias Archethic.Crypto

  alias Archethic.P2P.ListenerProtocol.MessageProducer
  alias Archethic.P2P.MemTable
  alias Archethic.P2P.Message
  alias Archethic.P2P.MessageEnvelop

  alias Broadway.Message, as: BroadwayMessage

  require Logger

  use Broadway

  def start_link(arg \\ []) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {MessageProducer, arg},
        transformer: {__MODULE__, :transform, []},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: System.schedulers_online() * 10, max_demand: 1]
      ]
    )
  end

  def transform(event, _) do
    %BroadwayMessage{
      data: event,
      acknowledger: {Broadway.NoopAcknowledger, _ack_ref = nil, _ack_data = nil}
    }
  end

  def handle_message(_, message, _context) do
    #    start_time = System.monotonic_time(:millisecond)

    BroadwayMessage.update_data(message, fn {socket, transport, data} ->
      message =
        data
        |> decode()
        |> process()
        |> encode()

      transport.send(socket, message)
      #      end_time = System.monotnonic_time(:millisecond)
      #      Logger.debug("Request processed in #{end_time - start_time} ms")
    end)
  end

  defp decode(data) do
    %MessageEnvelop{
      message_id: message_id,
      message: message,
      sender_public_key: sender_public_key
    } = MessageEnvelop.decode(data)

    MemTable.increase_node_availability(sender_public_key)
    {System.monotonic_time(:millisecond), message_id, message, sender_public_key}
  end

  defp process({_start_time, message_id, message, sender_public_key}) do
    response = Message.process(message)
    # end_time = System.monotonic_time(:millisecond)

    {message_id, response, sender_public_key}
  end

  defp encode({message_id, message, sender_public_key}) do
    %MessageEnvelop{
      message: message,
      message_id: message_id,
      sender_public_key: Crypto.first_node_public_key()
    }
    |> MessageEnvelop.encode(sender_public_key)
  end
end
