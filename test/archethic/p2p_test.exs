defmodule ArchEthic.P2PTest do
  use ArchEthicCase

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.Balance
  alias ArchEthic.P2P.Message.GetBalance
  alias ArchEthic.P2P.Message.RegisterBeaconUpdates
  alias ArchEthic.P2P.Node

  doctest ArchEthic.P2P

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  test "get_node_info/0 should return retrieve local node information" do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key()
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

      Enum.each(nodes, &P2P.add_and_connect_node/1)
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

  describe "broadcast_message/2" do
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

      Enum.each(nodes, &P2P.add_and_connect_node/1)
      {:ok, %{nodes: nodes}}
    end

    test "should send subscribe msg for register beacon update", %{nodes: nodes} do
      subset = <<0>>
      %Node{first_public_key: first_public_key} = nodes |> List.first()

      MockClient
      |> stub(:send_message, fn
        _, _ ->
          {:ok,
           %ArchEthic.BeaconChain.Slot{
             end_of_node_synchronizations: [],
             involved_nodes: "",
             p2p_view: %{availabilities: "", network_stats: []},
             slot_time: ~U[2021-11-01 07:16:00Z],
             subset: <<0>>,
             transaction_summaries: []
           }}
      end)

      assert :ok ==
               P2P.broadcast_message(nodes, %RegisterBeaconUpdates{
                 subset: subset,
                 node_public_key: first_public_key
               })
               
  describe "duplicating_node?/3" do
    test "should return true for duplicate node" do
      MockDB
      |> stub(:get_first_public_key, fn _ ->
        <<1::16, 1::8>>
      end)

      assert P2P.duplicating_node?(
               {127, 0, 0, 1},
               3000,
               <<1::16, 1::8>>,
               [
                 %Node{
                   ip: {127, 0, 0, 1},
                   port: 3000,
                   first_public_key: <<0::16, 0::8>>
                 }
               ]
             )
    end

    test "should return false for original node" do
      MockDB
      |> stub(:get_first_public_key, fn _ ->
        <<1::16, 1::8>>
      end)

      refute P2P.duplicating_node?(
               {127, 0, 0, 1},
               3000,
               <<1::16, 1::8>>,
               [
                 %Node{
                   ip: {127, 0, 0, 1},
                   port: 3000,
                   first_public_key: <<1::16, 1::8>>
                 }
               ]
             )
    end

    test "should return false for node with different ip/port" do
      MockDB
      |> stub(:get_first_public_key, fn _ ->
        <<1::16, 1::8>>
      end)

      refute P2P.duplicating_node?(
               {127, 0, 0, 2},
               3000,
               <<1::16, 1::8>>,
               [
                 %Node{
                   ip: {127, 0, 0, 1},
                   port: 3000,
                   first_public_key: <<1::16, 1::8>>
                 }
               ]
             )

      refute P2P.duplicating_node?(
               {127, 0, 0, 1},
               3001,
               <<1::16, 1::8>>,
               [
                 %Node{
                   ip: {127, 0, 0, 1},
                   port: 3000,
                   first_public_key: <<1::16, 1::8>>
                 }
               ]
             )
    end
  end
end
