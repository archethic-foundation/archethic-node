defmodule Uniris.P2PTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.Balance
  alias Uniris.P2P.Message.GetBalance
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

  describe "reply_first/3" do
    setup do
      nodes = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: "key1",
          last_public_key: "key1",
          geo_patch: "AAA",
          network_patch: "AAA",
          transport: MockTransport
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: "key2",
          last_public_key: "key2",
          geo_patch: "F23",
          network_patch: "F23",
          transport: MockTransport
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: "key3",
          last_public_key: "key3",
          geo_patch: "BCE",
          network_patch: "BCE",
          transport: MockTransport
        }
      ]

      Enum.each(nodes, &P2P.add_node/1)
      {:ok, %{nodes: nodes}}
    end

    test "should return response from the closest node", %{nodes: nodes} do
      MockClient
      |> expect(:send_message, fn _, %GetBalance{} ->
        {:ok, %Balance{}}
      end)

      assert {:ok, %Balance{}, %Node{first_public_key: "key1"}} =
               P2P.reply_first(
                 nodes,
                 %GetBalance{address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>},
                 patch: "AA2",
                 node_ack?: true
               )
    end

    test "should return response from the 2th closest node", %{nodes: nodes} do
      MockClient
      |> expect(:send_message, fn _, %GetBalance{} ->
        {:error, :network_issue}
      end)
      |> expect(:send_message, fn _, %GetBalance{} ->
        {:ok, %Balance{}}
      end)

      assert {:ok, %Balance{}, %Node{first_public_key: "key3"}} =
               P2P.reply_first(
                 nodes,
                 %GetBalance{address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>},
                 patch: "AA2",
                 node_ack?: true
               )
    end

    test "should return an error when no nodes replies", %{nodes: nodes} do
      MockClient
      |> stub(:send_message, fn _, %GetBalance{} ->
        {:error, :network_issue}
      end)

      assert {:error, :network_issue} =
               P2P.reply_first(
                 nodes,
                 %GetBalance{address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>},
                 patch: "AA2",
                 node_ack?: true
               )
    end

    test "broadcast_message/2 should execute the handler for all the nodes" do
      me = self()

      MockClient
      |> stub(:send_message, fn %Node{first_public_key: key}, %GetBalance{} ->
        send(me, key)
        {:ok, %Balance{}}
      end)

      [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: "key1",
          last_public_key: "key1",
          geo_patch: "AAA",
          network_patch: "AAA",
          transport: MockTransport
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: "key2",
          last_public_key: "key2",
          geo_patch: "F23",
          network_patch: "F23",
          transport: MockTransport
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: "key3",
          last_public_key: "key3",
          geo_patch: "BCE",
          network_patch: "BCE",
          transport: MockTransport
        }
      ]
      |> P2P.broadcast_message(%GetBalance{
        address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
      })

      assert_receive "key1"
      assert_receive "key2"
      assert_receive "key3"
    end
  end

  describe "reply_atomic/3" do
    setup do
      nodes = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: "key1",
          last_public_key: "key1",
          geo_patch: "AAA",
          network_patch: "AAA",
          transport: MockTransport
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: "key2",
          last_public_key: "key2",
          geo_patch: "F23",
          network_patch: "F23",
          transport: MockTransport
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: "key3",
          last_public_key: "key3",
          geo_patch: "BCE",
          network_patch: "BCE",
          transport: MockTransport
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: "key4",
          last_public_key: "key4",
          geo_patch: "2AC",
          network_patch: "2AC",
          transport: MockTransport
        }
      ]

      {:ok, %{nodes: nodes}}
    end

    test "should get all the same response", %{nodes: nodes} do
      MockClient
      |> stub(:send_message, fn _, %GetBalance{} ->
        {:ok, %Balance{}}
      end)

      {:ok, %Balance{}} =
        P2P.reply_atomic(nodes, 2, %GetBalance{
          address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
        })
    end

    test "should get take the next batch if the first batch has not atomic commitment", %{
      nodes: nodes
    } do
      MockClient
      |> stub(:send_message, fn
        %Node{first_public_key: "key1"}, %GetBalance{} ->
          {:ok, %Balance{uco: 10.0}}

        %Node{first_public_key: "key2"}, %GetBalance{} ->
          {:ok, %Balance{uco: 5.0}}

        _, %GetBalance{} ->
          {:ok, %Balance{uco: 10.0}}
      end)

      assert {:ok, %Balance{uco: 10.0}} =
               P2P.reply_atomic(nodes, 2, %GetBalance{
                 address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
               })
    end

    test "should return an error if no atomic commitment at all", %{nodes: nodes} do
      MockClient
      |> stub(:send_message, fn
        %Node{first_public_key: "key1"}, %GetBalance{} ->
          {:ok, %Balance{uco: 10.0}}

        %Node{first_public_key: "key2"}, %GetBalance{} ->
          {:ok, %Balance{uco: 5.0}}

        %Node{first_public_key: "key3"}, %GetBalance{} ->
          {:ok, %Balance{uco: 5.0}}

        %Node{first_public_key: "key4"}, %GetBalance{} ->
          {:ok, %Balance{uco: 10.0}}
      end)

      assert {:error, :network_issue} =
               P2P.reply_atomic(nodes, 2, %GetBalance{
                 address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
               })
    end
  end
end
