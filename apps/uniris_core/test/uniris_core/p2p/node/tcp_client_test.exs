defmodule UnirisCore.P2P.NodeTCPClientTest do
  use ExUnit.Case

  alias UnirisCore.P2P.NodeTCPClient

  defp recv(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        :gen_tcp.send(socket, data |> :erlang.binary_to_term() |> :erlang.term_to_binary())
        recv(socket)

      {:error, _} ->
        :ok
    end
  end

  defp acceptor(socket) do
    case :gen_tcp.accept(socket) do
      {:ok, client} ->
        spawn(fn -> recv(client) end)
        acceptor(socket)

      _ ->
        :error
    end
  end

  setup_all do
    {:ok, socket} = :gen_tcp.listen(7777, [:binary, packet: 4, active: false, reuseaddr: true])
    spawn(fn -> acceptor(socket) end)

    {:ok, %{port: 7777}}
  end

  test "start_link/3 should establish a connection and notify the connection", %{port: port} do
    {:ok, pid} = NodeTCPClient.start_link(ip: {127, 0, 0, 1}, port: port, parent_pid: self())

    %{socket: socket, ip: {127, 0, 0, 1}, port: port, parent_pid: _, queue: _} =
      :sys.get_state(pid)

    {:ok, {remote_addr, remote_port}} = :inet.peername(socket)
    assert remote_addr == {127, 0, 0, 1}
    assert remote_port == port

    assert_receive :connected

    :gen_tcp.close(socket)
  end

  test "send_message/2 should send a message and get results", %{port: port} do
    {:ok, socket} = NodeTCPClient.start_link(ip: {127, 0, 0, 1}, port: port, parent_pid: self())
    msg = :hello
    assert :hello == NodeTCPClient.send_message(socket, msg)
  end

  test "a connection closed should stop the process", %{port: port} do
    {:ok, pid} = NodeTCPClient.start_link(ip: {127, 0, 0, 1}, port: port, parent_pid: self())
    assert_receive :connected

    %{socket: socket} = :sys.get_state(pid)
    :gen_tcp.shutdown(socket, :read_write)
    Process.sleep(200)

    assert !Process.alive?(pid)
  end
end
