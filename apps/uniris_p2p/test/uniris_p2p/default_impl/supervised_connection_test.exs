defmodule UnirisP2P.DefaultImpl.SupervisedConnectionTest do
  use ExUnit.Case

  alias UnirisP2P.DefaultImpl.SupervisedConnection, as: Connection
  alias UnirisP2P.NodeRegistry

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    MockClient
    |> stub(:start_link, fn ip, _, pid ->
      case ip do
        {127, 0, 0, 1} ->
          send(pid, :connected)

        _ ->
          send(pid, :disconnected)
      end

      {:ok, self()}
    end)
    |> stub(:send_message, fn _, _msg ->
      {:ok, :response}
    end)

    :ok
  end

  test "start_link/3 should create a new connection and reach the connected state" do
    Registry.register(NodeRegistry, "public_key", [])
    {:ok, pid} = Connection.start_link(public_key: "public_key", ip: {127, 0, 0, 1}, port: 3000)
    Process.sleep(00)
    assert true == Process.alive?(pid)
    assert_receive {:"$gen_cast", :available}
    assert {:connected, _} = :sys.get_state(pid)
  end

  test "send_message/2 should send a message and get response" do
    {:ok, pid} = Connection.start_link(public_key: "public_key", ip: {127, 0, 0, 1}, port: 3000)
    Process.sleep(200)
    assert :response = Connection.send_message("public_key", :request)
    assert {:connected, _} = :sys.get_state(pid)
  end

  test "after error unavailability notification is sent" do
    Registry.register(NodeRegistry, "public_key2", [])
    {:ok, pid} = Connection.start_link(public_key: "public_key2", ip: {88, 0, 0, 1}, port: 3000)
    assert_receive {:"$gen_cast", :unavailable}
    assert {:disconnected, _} = :sys.get_state(pid)
  end
end
