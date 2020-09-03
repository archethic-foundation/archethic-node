defmodule Uniris.P2PTest do
  use UnirisCase, async: false
  doctest Uniris.P2P

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Node

  alias Uniris.Storage.Memory.NetworkLedger

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    :ok
  end

  test "node_info/0 should return retrieve node information or return error when not found" do
    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(),
      last_public_key: Crypto.node_public_key()
    })

    Process.sleep(100)

    assert {:ok, %Node{ip: {127, 0, 0, 1}}} = P2P.node_info()
  end

  describe "send_message/2" do
    test "should send the message and increase availability when successed" do
      expect(MockNodeClient, :send_message, fn _, _, msg -> {:ok, msg} end)

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key()
      }

      NetworkLedger.add_node_info(node)

      assert %Ok{} = P2P.send_message(node, %Ok{})

      {:ok, %Node{availability_history: <<1::1, _::bitstring>>}} =
        NetworkLedger.get_node_info(Crypto.node_public_key())
    end

    test "should send the message and decrease availability when an error occurs" do
      expect(MockNodeClient, :send_message, fn _, _, _msg -> {:error, :network_issue} end)

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key()
      }

      NetworkLedger.add_node_info(node)

      assert_raise RuntimeError, "Messaging error with 127.0.0.1:3000", fn ->
        P2P.send_message(node, %Ok{})
      end

      {:ok, %Node{availability_history: <<0::1, _::bitstring>>}} =
        NetworkLedger.get_node_info(Crypto.node_public_key())
    end
  end
end
