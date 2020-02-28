defmodule UnirisP2P.TCPClientTest do
  use ExUnit.Case

  alias UnirisP2P.TCPClient, as: Client
  alias UnirisCrypto, as: Crypto
  alias UnirisNetwork.Node
  alias UnirisChain.Transaction

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    port = Application.get_env(:uniris_p2p, :port)
    Crypto.generate_random_keypair(persistence: true)
    public_key = Crypto.last_node_public_key()

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

    MockNetwork
    |> stub(:node_info, fn _ -> node end)
    |> stub(:add_node, fn _ ->
      Registry.register(UnirisNetwork.NodeRegistry, public_key, [])
      :ok
    end)

    MockChain
    |> stub(:get_transaction, fn _ ->
      {:ok,
       %Transaction{
         address: "",
         type: :transfer,
         timestamp: DateTime.utc_now(),
         data: %{},
         previous_public_key: "",
         previous_signature: "",
         origin_signature: ""
       }}
    end)

    UnirisNetwork.add_node(node)

    {:ok, %{port: port, public_key: public_key}}
  end

  test "start_link/3 should establish a connection and notify availability", %{
    port: port,
    public_key: public_key
  } do
    {:ok, pid} = Client.start_link({127, 0, 0, 1}, port, public_key, self())

    Process.sleep(200)
    %{socket: socket, from: from} = :sys.get_state(pid)
    assert from == self()
    {:ok, {remote_addr, remote_port}} = :inet.peername(socket)
    assert remote_addr == {127, 0, 0, 1}
    assert remote_port == port

    assert_receive :connected
    assert_receive {:"$gen_cast", :available}
  end

  test "send_message/2 should send a message and get results", %{
    port: port,
    public_key: public_key
  } do
    {:ok, _} = Client.start_link({127, 0, 0, 1}, port, public_key, self())
    Client.send_message(public_key, {:get_transaction, Crypto.hash(:crypto.strong_rand_bytes(32))})
    assert_receive {:p2p_response, {:ok, {:ok, %Transaction{}}, public_key}}
  end

  test "closed connection by the client will notify unavailability of the node", %{port: port, public_key: public_key} do
    {:ok, pid} = Client.start_link({127, 0, 0, 1}, port, public_key, self())
    %{socket: socket} = :sys.get_state(pid)
    :gen_tcp.close(socket)
    assert_receive {:"$gen_cast", :unavailable}
  end

end
