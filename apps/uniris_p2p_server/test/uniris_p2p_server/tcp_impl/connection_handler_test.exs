defmodule UnirisP2PServer.TCPImpl.ConnectionHandlerTest do
  use ExUnit.Case

  alias UnirisCrypto, as: Crypto
  alias UnirisP2P.Node

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  @tcp_options [:binary, packet: 4, active: false]

  setup do
    port = Application.get_env(:uniris_p2p_server, :port)
    {public_key, _} = Crypto.generate_deterministic_keypair("myseed")

    node = %Node{
      ip: {127, 0, 0, 1},
      port: port,
      first_public_key: public_key,
      last_public_key: public_key,
      geo_patch: "AAA",
      network_patch: "AAA",
      availability: 1,
      average_availability: 1
    }

    {:ok, %{port: port, node: node}}
  end

  test "send message node should retrieve data and mark the node as available", %{
    port: port,
    node: node
  } do
    Registry.register(UnirisP2P.NodeRegistry, node.ip, [])

    MockP2P
    |> stub(:list_nodes, fn -> [] end)

    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, @tcp_options)
    :ok = :gen_tcp.send(socket, :erlang.term_to_binary(:new_seeds, [:compressed]))
    Process.sleep(200)

    assert_receive {:"$gen_cast", :available}

    {:ok, data} = :gen_tcp.recv(socket, 0)
    assert [] = :erlang.binary_to_term(data)
  end

  test "closed connection with an internal should notify unavailability of the node", %{
    port: port,
    node: node
  } do
    Registry.register(UnirisP2P.NodeRegistry, node.ip, [])

    MockP2P
    |> stub(:node_info, fn _ -> {:ok, node} end)

    MockChain
    |> stub(:get_transaction, fn _ -> {:error, :transaction_not_exists} end)

    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, @tcp_options)
    :gen_tcp.send(socket, :erlang.term_to_binary({:get_transaction, Crypto.hash("")}, [:compressed]))
    assert_receive {:"$gen_cast", :available}
    :gen_tcp.close(socket)
    assert_receive {:"$gen_cast", :unavailable}
  end
end
