defmodule Archethic.P2P.ListenerProtocol do
  @moduledoc false

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

    %Archethic.P2P.MessageEnvelop{
      message_id: message_id,
      message: message,
      sender_public_key: sender_public_key
    } = Archethic.P2P.MessageEnvelop.decode(msg)

    Archethic.P2P.MemTable.increase_node_availability(sender_public_key)
    Archethic.P2P.Client.set_connected(sender_public_key)

    Task.Supervisor.start_child(TaskSupervisor, fn ->
      response = Archethic.P2P.Message.process(message)

      encoded_response =
        %Archethic.P2P.MessageEnvelop{
          message: response,
          message_id: message_id,
          sender_public_key: Archethic.Crypto.first_node_public_key()
        }
        |> Archethic.P2P.MessageEnvelop.encode(sender_public_key)

      transport.send(socket, encoded_response)
    end)

    {:noreply, state}
  end

  def handle_info({_transport_closed, _socket}, state = %{ip: ip, port: port}) do
    Logger.warning("Connection closed for #{:inet.ntoa(ip)}:#{port}")
    {:stop, :normal, state}
  end
end
