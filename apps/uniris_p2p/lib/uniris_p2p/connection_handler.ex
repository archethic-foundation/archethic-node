defmodule UnirisP2P.ConnectionHandler do
  @moduledoc false

  alias UnirisP2P.Message
  alias UnirisNetwork.Node

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
    result =
      case Message.decode(data) do
        {:ok, message, public_key} ->
          Node.available(public_key)
          process_message(message, public_key)

        _ ->
          {:error, :invalid_message}
      end

    encoded_payload = Message.encode(result)
    transport.send(socket, encoded_payload)

    {:noreply, state}
  end

  def handle_info({_, _}, state), do: {:stop, :normal, state}

  defp process_message(message, from) when is_list(message) do
    Task.async_stream(message, &Message.process(&1, from))
    |> Enum.into([], fn {:ok, res} -> res end)
    |> reduce_message_processing([])
  end

  defp process_message(message, from), do: Message.process(message, from)

  defp reduce_message_processing([{:error, reason} | _], _) do
    {:error, reason}
  end

  defp reduce_message_processing([result | rest], acc = []) do
    reduce_message_processing(rest, acc ++ [result])
  end
end
