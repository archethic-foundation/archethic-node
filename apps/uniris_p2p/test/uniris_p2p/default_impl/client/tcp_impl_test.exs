defmodule UnirisP2P.DefaultImpl.SupervisedConnection.Client.TCPImplTest do
  use ExUnit.Case

  alias UnirisP2P.DefaultImpl.SupervisedConnection.Client.TCPImpl, as: Client
  alias UnirisCrypto, as: Crypto

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
    {:ok, pid} = Client.start_link({127, 0, 0, 1}, port, self())
    %{socket: socket} = :sys.get_state(pid)

    {:ok, {remote_addr, remote_port}} = :inet.peername(socket)
    assert remote_addr == {127, 0, 0, 1}
    assert remote_port == port

    assert_receive :connected

    :gen_tcp.close(socket)
  end

  test "send_message/2 should send a message and get results", %{port: port} do
    {:ok, socket} = Client.start_link({127, 0, 0, 1}, port, self())
    msg = {:get_transaction, Crypto.hash(:crypto.strong_rand_bytes(32))}
    {:ok, result} = Client.send_message(socket, msg)
    assert result == msg
  end

  test "a connection closed should get a disconnection message", %{port: port} do
    {:ok, pid} = Client.start_link({127, 0, 0, 1}, port, self())
    assert_receive :connected

    %{socket: socket} = :sys.get_state(pid)
    :gen_tcp.shutdown(socket, :read_write)

    assert_receive :disconnected
  end
end
