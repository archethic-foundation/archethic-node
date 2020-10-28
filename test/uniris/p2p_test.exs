defmodule Uniris.P2PTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Node

  doctest Uniris.P2P

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  test "get_node_info/0 should return retrieve local node information" do
    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(),
      last_public_key: Crypto.node_public_key()
    })

    Process.sleep(100)

    assert %Node{ip: {127, 0, 0, 1}} = P2P.get_node_info()
  end

  describe "send_message/2" do
    test "should send the message and increase availability when succeed" do
      expect(MockTransport, :send_message, fn _, _, msg -> {:ok, msg} end)

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        transport: MockTransport
      }

      P2P.add_node(node)

      assert %Ok{} = P2P.send_message(node, %Ok{})

      {:ok, %Node{availability_history: <<1::1, _::bitstring>>}} =
        P2P.get_node_info(Crypto.node_public_key())
    end

    test "should send the message and decrease availability when an error occurs" do
      expect(MockTransport, :send_message, fn _, _, _msg -> {:error, :network_issue} end)

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        transport: MockTransport
      }

      P2P.add_node(node)

      assert_raise RuntimeError,
                   "Messaging error with 127.0.0.1:3000 - reason: network_issue",
                   fn ->
                     P2P.send_message(node, %Ok{})
                   end

      {:ok, %Node{availability_history: <<0::1, _::bitstring>>}} =
        P2P.get_node_info(Crypto.node_public_key())
    end
  end
end
