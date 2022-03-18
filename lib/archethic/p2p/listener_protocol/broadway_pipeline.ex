defmodule ArchEthic.P2P.ListenerProtocol.BroadwayPipeline do
  @moduledoc false

  alias ArchEthic.Crypto

  alias ArchEthic.P2P.ListenerProtocol.BroadwayPipelineRegistry
  alias ArchEthic.P2P.ListenerProtocol.MessageProducer
  alias ArchEthic.P2P.MemTable
  alias ArchEthic.P2P.Message
  alias ArchEthic.P2P.MessageEnvelop

  alias Broadway.Message, as: BroadwayMessage

  require Logger

  use Broadway

  def start_link(arg) do
    socket = Keyword.get(arg, :socket)
    transport = Keyword.get(arg, :transport)
    ip = Keyword.get(arg, :ip)
    port = Keyword.get(arg, :port)
    conn_pid = Keyword.get(arg, :conn_pid)

    Broadway.start_link(__MODULE__,
      name: {:via, Registry, {BroadwayPipelineRegistry, {ip, port, conn_pid}}},
      context: %{
        socket: socket,
        transport: transport
      },
      producer: [
        module: {MessageProducer, arg},
        transformer: {__MODULE__, :transform, []},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 5, max_demand: 1]
      ]
    )
  end

  def process_name(
        {:via, Registry, {BroadwayPipelineRegistry, {ip, port, conn_pid}}},
        base_name
      ) do
    pid_string = conn_pid |> :erlang.pid_to_list() |> :erlang.list_to_binary()
    :"#{:inet.ntoa(ip)}:#{port}.#{pid_string}.Broadway.#{base_name}"
  end

  def transform(event, _) do
    %BroadwayMessage{
      data: event,
      acknowledger: {Broadway.NoopAcknowledger, _ack_ref = nil, _ack_data = nil}
    }
  end

  def handle_message(_, message, %{socket: socket, transport: transport}) do
    BroadwayMessage.update_data(message, fn data ->
      message =
        data
        |> decode()
        |> process()
        |> encode()

      transport.send(socket, message)
    end)
  end

  defp decode(data) do
    %MessageEnvelop{
      message_id: message_id,
      message: message,
      sender_public_key: sender_public_key
    } = MessageEnvelop.decode(data)

    #    Logger.debug("Receive message #{Message.name(message)}",
    #      node: Base.encode16(sender_public_key),
    #      message_id: message_id
    #    )

    MemTable.increase_node_availability(sender_public_key)
    {System.monotonic_time(:millisecond), message_id, message, sender_public_key}
  end

  defp process({_start_time, message_id, message, sender_public_key}) do
    response = Message.process(message)
    # end_time = System.monotonic_time(:millisecond)

    #    Logger.debug("Message #{Message.name(message)} processed in #{end_time - start_time} ms",
    #      node: Base.encode16(sender_public_key),
    #      message_id: message_id
    #    )

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
