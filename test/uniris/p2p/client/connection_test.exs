defmodule Uniris.P2P.ClientConnectionTest do
  use UnirisCase

  alias Uniris.P2P.ClientConnection

  import Mox

  @moduletag capture_log: true

  setup :verify_on_exit!
  setup :set_mox_global

  test "start_link/1 should initiate a worker by establishing a connection to a remote endpoint" do
    MockTransport
    |> expect(:connect, fn _, _, _, _ -> {:ok, make_ref()} end)
    |> expect(:read_from_socket, fn _, _, _, _ -> :ok end)

    {:ok, pid} =
      ClientConnection.start_link(
        ip: {127, 0, 0, 1},
        port: 3000,
        transport: MockTransport,
        node_public_key: :crypto.strong_rand_bytes(32)
      )

    Process.sleep(100)

    assert {:connected, %{socket: _, ip: {127, 0, 0, 1}, port: 3000, multiplexer_pid: _}} =
             :sys.get_state(pid)
  end

  describe "send_message/3" do
    test "should send a message to a given topic to reach the remote endpoint and get some data" do
      MockTransport
      |> expect(:connect, fn _, _, _, _ -> {:ok, make_ref()} end)
      |> expect(:read_from_socket, fn _, fun, _, _ ->
        pid =
          spawn(fn ->
            receive do
              {:send, data} ->
                fun.(data)
            end
          end)

        :persistent_term.put(:registry, pid)
        :ok
      end)
      |> expect(:send_message, fn _, data ->
        send(:persistent_term.get(:registry), {:send, data})
        :ok
      end)

      {:ok, pid} =
        ClientConnection.start_link(
          ip: {127, 0, 0, 1},
          port: 3000,
          transport: MockTransport,
          node_public_key: :crypto.strong_rand_bytes(32)
        )

      assert {:ok, "hello"} = ClientConnection.send_message(pid, "hello")
    end

    test "should reconnect if the connection is closed during the sending and return an error" do
      MockTransport
      |> stub(:connect, fn _, _, _, _ -> {:ok, self()} end)
      |> stub(:send_message, fn _, _ -> {:error, :closed} end)
      |> stub(:read_from_socket, fn _, _, _, _ -> :ok end)

      {:ok, pid} =
        ClientConnection.start_link(
          ip: {127, 0, 0, 1},
          port: 3000,
          transport: MockTransport,
          node_public_key: :crypto.strong_rand_bytes(32)
        )

      assert {:error, :disconnected} = ClientConnection.send_message(pid, "hello")
      Process.sleep(100)
      assert {:connected, _} = :sys.get_state(pid)
    end

    test "should reconnect if the connection is timeout during the sending and return an error" do
      MockTransport
      |> stub(:connect, fn _, _, _, _ -> {:ok, self()} end)
      |> stub(:send_message, fn _, _ -> {:error, :timeout} end)
      |> stub(:read_from_socket, fn _, _, _, _ -> :ok end)

      {:ok, pid} =
        ClientConnection.start_link(
          ip: {127, 0, 0, 1},
          port: 3000,
          transport: MockTransport,
          node_public_key: :crypto.strong_rand_bytes(32)
        )

      assert {:error, :timeout} = ClientConnection.send_message(pid, "hello")
      Process.sleep(100)
      assert {:connected, _} = :sys.get_state(pid)
    end
  end
end
