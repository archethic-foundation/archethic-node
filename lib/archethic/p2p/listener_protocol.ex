defmodule Archethic.P2P.ListenerProtocol do
  @moduledoc false
  # ListenerProtocol handles Incoming new messages from other nodes and
  # no response is processed here.
  # Connection modules handles this nodes request get messages and
  # then its response is processed.

  require Logger

  alias Archethic.TaskSupervisor

  @behaviour :ranch_protocol

  def start_link(ref, transport, opts) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [{ref, transport, opts}])
    {:ok, pid}
  end

  def init({ref, transport, opts}) do
    {:ok, socket} = :ranch.handshake(ref)
    :ok = transport.setopts(socket, opts)

    {:ok, {ip, port}} = :inet.peername(socket)

    :gen_server.enter_loop(__MODULE__, [], %{
      socket: socket,
      transport: transport,
      ip: ip,
      port: port
    })
  end

  def handle_info(
        {_transport, socket, msg},
        state = %{transport: transport}
      ) do
    :inet.setopts(socket, active: :once)

    Task.Supervisor.start_child(TaskSupervisor, fn ->
      start_decode_time = System.monotonic_time()

      %Archethic.P2P.MessageEnvelop{
        message_id: message_id,
        message: message,
        sender_public_key: sender_public_key
      } = Archethic.P2P.MessageEnvelop.decode(msg)

      :telemetry.execute(
        [:archethic, :p2p, :decode_message],
        %{duration: System.monotonic_time() - start_decode_time},
        %{message: Archethic.P2P.Message.name(message)}
      )

      start_processing_time = System.monotonic_time()
      response = Archethic.P2P.Message.process(message, sender_public_key)

      :telemetry.execute(
        [:archethic, :p2p, :handle_message],
        %{
          duration: System.monotonic_time() - start_processing_time
        },
        %{message: Archethic.P2P.Message.name(message)}
      )

      start_encode_time = System.monotonic_time()

      encoded_response =
        %Archethic.P2P.MessageEnvelop{
          message: response,
          message_id: message_id,
          sender_public_key: Archethic.Crypto.first_node_public_key()
        }
        |> Archethic.P2P.MessageEnvelop.encode(sender_public_key)

      :telemetry.execute(
        [:archethic, :p2p, :encode_message],
        %{duration: System.monotonic_time() - start_encode_time},
        %{message: Archethic.P2P.Message.name(message)}
      )

      start_sending_time = System.monotonic_time()
      transport.send(socket, encoded_response)

      :telemetry.execute(
        [:archethic, :p2p, :transport_sending_message],
        %{duration: System.monotonic_time() - start_sending_time},
        %{message: Archethic.P2P.Message.name(message)}
      )
    end)

    {:noreply, state}
  end

  def handle_info({_transport_closed, _socket}, state = %{ip: ip, port: port}) do
    Logger.warning("Connection closed for #{:inet.ntoa(ip)}:#{port}")
    {:stop, :normal, state}
  end
end
