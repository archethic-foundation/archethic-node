defmodule UnirisP2P.ConnectionHandler do
  @moduledoc false

  alias UnirisP2P.Message
  alias UnirisNetwork, as: Network
  alias UnirisNetwork.Node

  use GenServer

  require Logger

  @tcp_options [:binary, active: :once, packet: 4]

  def start_link(ref, socket, transport, _opts) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [{ref, socket, transport}])
    {:ok, pid}
  end

  def init({ref, socket, transport}) do
    {address, _port} = parse_socket(socket)
    %Node{last_public_key: public_key} = Network.node_info(address)
    Node.available(public_key)
    Logger.info("New connection from #{stringify_address(address)}")
    :ok = :ranch.accept_ack(ref)
    :ok = transport.setopts(socket, @tcp_options)

    :gen_server.enter_loop(__MODULE__, [], %{
      socket: socket,
      transport: transport,
      node_public_key: public_key
    })
  end

  def handle_info(
        {_, socket, data},
        state = %{transport: transport, node_public_key: node_public_key}
      ) do
    {message, result, public_key} =
      case Message.decode(data) do
        {:ok, message, public_key} when node_public_key == public_key ->
          Logger.info(
            "Start process message #{inspect(message)} from #{public_key |> Base.encode16()}"
          )

          {message, process_message(message, public_key), public_key}

        _ ->
          {:error, :invalid_message}
      end

    Logger.info("End process message #{inspect(message)} from #{public_key |> Base.encode16()}")
    encoded_payload = Message.encode(result)
    transport.send(socket, encoded_payload)

    :inet.setopts(socket, @tcp_options)

    {:noreply, state}
  end

  def handle_info({:tcp_closed, _socket}, state = %{node_public_key: public_key}) do
    Node.unavailable(public_key)
    {:stop, :normal, state}
  end

  def handle_info(error_reason, state = %{node_public_key: public_key}) do
    Node.unavailable(public_key)
    {:stop, error_reason, state}
  end

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

  defp parse_socket(socket) do
    {:ok, {addr, port}} = :inet.peername(socket)
    {addr, port}
  end

  defp stringify_address(address) do
    address
    |> :inet_parse.ntoa()
    |> to_string()
  end
end
