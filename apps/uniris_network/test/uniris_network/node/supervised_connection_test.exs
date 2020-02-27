defmodule UnirisNetwork.Node.SupervisedConnectionTest do
  use ExUnit.Case

  alias UnirisNetwork.Node.SupervisedConnection, as: Connection

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    MockP2P
    |> stub(:start_link, fn _, _, public_key, pid ->
      case public_key do
        "public_key" ->
          send(pid, :connected)
          {:ok, self()}

        _ ->
          send(pid, {:DOWN, make_ref(), :process, pid, :connection_closed})
          {:ok, self()}
      end
    end)
    |> stub(:send_message, fn _, msg ->
      case msg do
        {from, :request} ->
          send(from, {:p2p_response, {:ok, :response, "public_key"}})

        {from, :long_request} ->
          Process.sleep(1000)
          send(from, {:p2p_response, {:ok, :response, "public_key"}})
      end

      :ok
    end)

    :ok
  end

  test "start_link/3 should create a new state machine" do
    Registry.register(UnirisNetwork.NodeRegistry, "public_key", self())
    {:ok, pid} = Connection.start_link("public_key", "127.0.0.1", 3000)
    Process.sleep(200)
    assert true == Process.alive?(pid)
    assert {:connected, %{client_pid: _}} = :sys.get_state(pid)
    assert_receive {:"$gen_cast", :available}
  end

  test "send_message/2 should send a message and get response" do
    {:ok, pid} = Connection.start_link("public_key", "127.0.0.1", 3000)
    Process.sleep(200)
    assert {:ok, :response} = Connection.send_message(pid, {pid, :request})
    assert {:connected, %{queue: {[], []}}} = :sys.get_state(pid)
  end

  test "send_message/2 should queue messages" do
    {:ok, pid} = Connection.start_link("public_key", "127.0.0.1", 3000)
    Process.sleep(200)
    me = self()

    spawn(fn ->
      {:ok, :response} = Connection.send_message(pid, {pid, :long_request})
      send(me, :response)
    end)

    {:ok, :response} = Connection.send_message(pid, {pid, :request})
    assert_receive :response, 1000
  end

  test "after error unavailability notification is sent" do
    Registry.register(UnirisNetwork.NodeRegistry, "public_key2", self())
    
    {:ok, pid} = Connection.start_link("public_key2", "127.0.0.1", 3000)
    Process.sleep(200)
    assert_receive {:"$gen_cast", :unavailable}
  end
  
end
