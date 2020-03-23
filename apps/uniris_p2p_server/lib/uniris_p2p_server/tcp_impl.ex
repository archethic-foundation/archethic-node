defmodule UnirisP2PServer.TCPImpl do
  @moduledoc false
  require Logger

  use GenServer

  alias UnirisP2PServer.TaskSupervisor
  alias UnirisP2PServer.MessageHandler
  alias UnirisP2P.Node

  @behaviour UnirisP2PServer.Impl

  require Logger

  @impl true
  def start_link(port) do
    GenServer.start_link(__MODULE__, [port], name: TCP)
  end

  @impl true
  def init([port]) do

    {:ok, listen_socket} =
      :gen_tcp.listen(port, [:binary, {:packet, 4}, {:active, false}, {:reuseaddr, true}])
    Logger.info("P2P Server running on port #{port}")

    Enum.each(0..10, fn _ ->
      Task.Supervisor.start_child(TaskSupervisor, fn -> loop_acceptor(listen_socket) end)
    end)

    {:ok, []}
  end

  def loop_acceptor(listen_socket) do
    {:ok, socket} = :gen_tcp.accept(listen_socket)
    {address, _port} = parse_socket(socket)

    Node.available(address)

    {:ok, pid} = Task.Supervisor.start_child(TaskSupervisor, fn ->  recv_loop(socket, address) end)
    :ok = :gen_tcp.controlling_process(socket, pid)

    loop_acceptor(listen_socket)
  end

  def recv_loop(socket, address) do
    case :gen_tcp.recv(socket, 0) do
        {:ok, data} ->
          result = data
          |> :erlang.binary_to_term([:safe])
          |> process_message
          :gen_tcp.send(socket, :erlang.term_to_binary(result, [:compressed]))
          recv_loop(socket, address)
      {:error, :closed} ->
        :gen_tcp.close(socket)
        Node.unavailable(address)
      {:error, :enotconn} ->
        :gen_tcp.close(socket)
        Node.unavailable(address)
    end
  end

  defp process_message(messages) when is_list(messages) do
    do_process_messages(messages, [])
  end

  defp process_message(message), do: MessageHandler.process(message)


  defp do_process_messages([message | rest], acc) do
    result = MessageHandler.process(message)
    do_process_messages(rest, [result | acc])
  end

  defp do_process_messages([], acc), do: Enum.reverse(acc)



  defp parse_socket(socket) do
    {:ok, {addr, port}} = :inet.peername(socket)
    {addr, port}
  end
end
