defmodule Archethic.P2P.ListenerProtocol do
  @moduledoc false
  # ListenerProtocol handles Incoming new messages from other nodes and
  # no response is processed here.
  # Connection modules handles this nodes request get messages and
  # then its response is processed.

  require Logger

  alias Archethic.Crypto
  alias Archethic.P2P.Message
  alias Archethic.P2P.MessageEnvelop
  alias Archethic.TaskSupervisor
  alias Archethic.Utils

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
        {_transport, socket, err},
        state = %{transport: transport, ip: ip, port: port}
      )
      when is_atom(err) do
    Logger.warning(
      "Received an error from tcp listener (ip: #{inspect(ip)}, port: #{port}): #{inspect(err)}"
    )

    transport.close(socket)
    {:noreply, state}
  end

  def handle_info(
        {_transport, socket, msg},
        state = %{transport: transport}
      ) do
    :inet.setopts(socket, active: :once)

    Task.Supervisor.start_child(TaskSupervisor, fn ->
      do_handle_message(msg, transport, socket)
    end)

    {:noreply, state}
  end

  def handle_info({_transport_closed, _socket}, state = %{ip: ip, port: port}) do
    Logger.warning("Connection closed for #{:inet.ntoa(ip)}:#{port}")
    {:stop, :normal, state}
  end

  defp do_handle_message(msg, transport, socket) do
    case do_decode_msg(msg) do
      nil ->
        transport.close(socket)

      %MessageEnvelop{
        message_id: message_id,
        message: message,
        sender_public_key: sender_pkey,
        signature: signature
      } ->
        valid_signature? =
          Crypto.verify?(
            signature,
            Message.encode(message) |> Utils.wrap_binary(),
            sender_pkey
          )

        if valid_signature? do
          do_process_msg(message, sender_pkey)
          |> do_encode_response(message_id, sender_pkey)
          |> do_reply(transport, socket, message)
        else
          transport.close(socket)
        end
    end
  end

  # msg is the bytes coming from TCP
  # message is the struct
  defp do_decode_msg(msg) do
    start_decode_time = System.monotonic_time()

    MessageEnvelop.decode(msg)
    |> tap(fn %MessageEnvelop{message: message} ->
      :telemetry.execute(
        [:archethic, :p2p, :decode_message],
        %{duration: System.monotonic_time() - start_decode_time},
        %{message: Message.name(message)}
      )
    end)
  rescue
    _ ->
      Logger.warning("Received an invalid message")
      nil
  end

  defp do_process_msg(message, sender_pkey) do
    start_processing_time = System.monotonic_time()

    Message.process(message, sender_pkey)
    |> tap(fn _ ->
      :telemetry.execute(
        [:archethic, :p2p, :handle_message],
        %{
          duration: System.monotonic_time() - start_processing_time
        },
        %{message: Message.name(message)}
      )
    end)
  end

  defp do_encode_response(response, message_id, sender_pkey) do
    start_encode_time = System.monotonic_time()

    response_signature =
      response
      |> Message.encode()
      |> Utils.wrap_binary()
      |> Crypto.sign_with_first_node_key()

    %MessageEnvelop{
      message: response,
      message_id: message_id,
      sender_public_key: Crypto.first_node_public_key(),
      signature: response_signature
    }
    |> MessageEnvelop.encode(sender_pkey)
    |> tap(fn _ ->
      :telemetry.execute(
        [:archethic, :p2p, :encode_message],
        %{duration: System.monotonic_time() - start_encode_time},
        %{message: Message.name(response)}
      )
    end)
  end

  defp do_reply(encoded_response, transport, socket, message) do
    start_sending_time = System.monotonic_time()

    transport.send(socket, encoded_response)
    |> tap(fn _ ->
      :telemetry.execute(
        [:archethic, :p2p, :transport_sending_message],
        %{duration: System.monotonic_time() - start_sending_time},
        %{message: Message.name(message)}
      )
    end)
  end
end
