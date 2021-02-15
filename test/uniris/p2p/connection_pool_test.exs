defmodule Uniris.P2P.ConnectionPoolTest do
  use ExUnit.Case

  alias Uniris.P2P.ConnectionPool
  alias Uniris.P2P.Node

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  test "add_connection_pool/1 should add a connection pool for the given node" do
    node = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      transport: MockTransport,
      first_public_key: :crypto.strong_rand_bytes(32)
    }

    MockTransport
    |> stub(:connect, fn _, _, _, _ -> {:ok, self()} end)

    {:ok, _pid} = ConnectionPool.add_node_connection_pool(node)

    assert node.first_public_key
           |> ConnectionPool.workers()
           |> Enum.all?(fn pid ->
             assert {:connected, %{ip: {127, 0, 0, 1}, port: 3000}} = :sys.get_state(pid)
           end)
  end

  test "send_message/2 should distribute messages to the node workers" do
    node = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      transport: MockTransport,
      first_public_key: :crypto.strong_rand_bytes(32)
    }

    MockTransport
    |> stub(:connect, fn _, _, _, _ -> {:ok, self()} end)
    |> stub(:send_message, fn _, _ -> :ok end)
    |> stub(:read_from_socket, fn _, _, _ ->
      Process.sleep(100)
      {:ok, "hello"}
    end)

    {:ok, _pid} = ConnectionPool.add_node_connection_pool(node)

    assert 100 ==
             1..100
             |> Task.async_stream(fn _ ->
               ConnectionPool.send_message(node.first_public_key, "hello")
             end)
             |> Enum.into([], fn {:ok, res} -> res end)
             |> Enum.count()
  end
end
