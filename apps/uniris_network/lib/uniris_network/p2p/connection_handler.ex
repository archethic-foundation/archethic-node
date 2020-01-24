defmodule UnirisNetwork.P2P.ConnectionHandler do
  @moduledoc false

  alias UnirisNetwork.P2P.Request
  alias UnirisNetwork.P2P.Payload

  use GenServer

  @options [:binary, active: true, packet: 4]

  def start_link(ref, socket, transport, _opts) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [{ref, socket, transport}])
    {:ok, pid}
  end

  def init({ref, socket, transport}) do
    :ok = :ranch.accept_ack(ref)
    :ok = transport.setopts(socket, @options)
    :gen_server.enter_loop(__MODULE__, [], %{socket: socket, transport: transport})
  end

  def handle_info({_, socket, data}, state = %{transport: transport}) do
    result = Request.execute(data)
    encoded_payload = Payload.encode(result)
    transport.send(socket, encoded_payload)

    {:noreply, state}
  end

  def handle_info({_, _}, state), do: {:stop, :normal, state}
end
