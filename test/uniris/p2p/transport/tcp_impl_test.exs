defmodule Uniris.P2P.Transport.TCPImplTest do
  use ExUnit.Case

  alias Uniris.P2P.Endpoint.ConnectionSupervisor
  alias Uniris.P2P.Transport.TCPImpl, as: TCPTransport

  alias Uniris.P2P.Message.AcknowledgeStorage
  alias Uniris.P2P.Message.Ok

  @port 13_939

  setup do
    start_supervised!({Task.Supervisor, name: Uniris.P2P.Endpoint.ConnectionSupervisor})
    :ok
  end

  test "listen/1 should open a port with tcp endpoint" do
    assert {:ok, socket} = TCPTransport.listen(@port)
    assert :ok = :gen_tcp.close(socket)
  end

  test "accept/1 should accept an incoming connection" do
    assert {:ok, listen_socket} = TCPTransport.listen(@port)

    spawn(fn -> TCPTransport.accept(listen_socket) end)

    assert {:ok, _socket} =
             :gen_tcp.connect({127, 0, 0, 1}, @port, [:binary, packet: 4, active: false])

    Process.sleep(500)
    [pid] = Task.Supervisor.children(ConnectionSupervisor)

    assert {Uniris.P2P.Transport.TCPImpl, :"-accept/1-fun-0-", 0} =
             pid
             |> Process.info()
             |> get_in([:dictionary, :"$initial_call"])

    assert :ok = :gen_tcp.close(listen_socket)
  end

  test "send_message/3 should send a message to remote endpoint" do
    assert {:ok, listen_socket} = TCPTransport.listen(@port)

    spawn(fn -> assert TCPTransport.accept(listen_socket) end)
    Process.sleep(500)

    assert {:ok, %Ok{}} =
             TCPTransport.send_message({127, 0, 0, 1}, @port, %AcknowledgeStorage{
               address: <<0::8, :crypto.hash(:sha256, "Alice1")::binary>>
             })

    assert :ok = :gen_tcp.close(listen_socket)
  end
end
