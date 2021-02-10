defmodule Uniris.P2P.ConnectionPool.WorkerTest do
  use ExUnit.Case

  alias Uniris.P2P.ConnectionPool.Worker

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  test "start_link/1 should initiate a worker by establishing a connection to a remote endpoint" do
    MockTransport
    |> expect(:connect, fn _, _, _, _ -> {:ok, self()} end)

    {:ok, pid} = Worker.start_link(ip: {127, 0, 0, 1}, port: 3000, transport: MockTransport)
    Process.sleep(100)
    assert {:connected, %{socket: _, ip: {127, 0, 0, 1}, port: 3000}} = :sys.get_state(pid)
  end

  describe "send_message/2" do
    test "should send message to the remote endpoint and get the data" do
      MockTransport
      |> expect(:connect, fn _, _, _, _ -> {:ok, self()} end)
      |> expect(:send_message, fn _, _ -> :ok end)
      |> expect(:read_from_socket, fn _, _, _ -> {:ok, "hello"} end)

      {:ok, pid} = Worker.start_link(ip: {127, 0, 0, 1}, port: 3000, transport: MockTransport)
      assert {:ok, "hello"} = Worker.send_message(pid, "hello")
    end

    test "should reconnect if the connection is closed during the sending and return an error" do
      MockTransport
      |> stub(:connect, fn _, _, _, _ -> {:ok, self()} end)
      |> expect(:send_message, fn _, _ -> {:error, :closed} end)

      {:ok, pid} = Worker.start_link(ip: {127, 0, 0, 1}, port: 3000, transport: MockTransport)
      assert {:error, :disconnected} = Worker.send_message(pid, "hello")
      Process.sleep(100)
      assert {:connected, _} = :sys.get_state(pid)
    end

    test "should reconnect if the connection is timeout during the sending and return an error" do
      MockTransport
      |> stub(:connect, fn _, _, _, _ -> {:ok, self()} end)
      |> stub(:send_message, fn _, _ -> {:error, :timeout} end)

      {:ok, pid} = Worker.start_link(ip: {127, 0, 0, 1}, port: 3000, transport: MockTransport)
      assert {:error, :network_issue} = Worker.send_message(pid, "hello", 2)
      Process.sleep(100)
      assert {:connected, _} = :sys.get_state(pid)
    end
  end
end
