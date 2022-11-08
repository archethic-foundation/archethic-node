defmodule Archethic.SelfRepair.NotifierTest do
  use ArchethicCase

  alias Archethic.{
    Crypto,
    P2P,
    P2P.Node,
    P2P.Message.ShardRepair,
    SelfRepair.Notifier,
    TransactionChain.Transaction
  }

  import Mox

  describe "Unit Tests" do
    setup do
      P2P.add_and_connect_node(
        node0 = %Node{
          first_public_key: Crypto.first_node_public_key(),
          last_public_key: Crypto.first_node_public_key(),
          ip: {127, 0, 0, 1},
          port: 3000,
          authorized?: true,
          available?: true,
          authorization_date: ~U[2022-10-01 00:00:00Z],
          geo_patch: "AAA"
        }
      )

      P2P.add_and_connect_node(
        node1 = %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3001,
          available?: true,
          authorized?: true,
          authorization_date: ~U[2022-10-05 00:00:00Z],
          geo_patch: "CCC"
        }
      )

      P2P.add_and_connect_node(
        node2 = %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3002,
          available?: true,
          authorized?: true,
          authorization_date: ~U[2022-10-07 00:00:00Z],
          geo_patch: "BBB"
        }
      )

      P2P.add_and_connect_node(
        node3 = %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3003,
          available?: true,
          authorized?: true,
          authorization_date: ~U[2022-10-10 12:00:00Z],
          geo_patch: "DDD"
        }
      )

      %{node0: node0, node1: node1, node2: node2, node3: node3}
    end

    test "network_chain?/1", _ do
      MockDB
      |> stub(:get_transaction, fn
        "txn0", [:type] ->
          {:ok, %Transaction{type: :transfer}}

        "network_txn0", [:type] ->
          {:ok, %Transaction{type: Enum.random(Transaction.list_network_type())}}
      end)

      assert Notifier.network_chain?("network_txn0")
      refute Notifier.network_chain?("txn0")
    end

    test "get_nodes_list/1", %{
      node0: %Node{first_public_key: node0},
      node1: %Node{first_public_key: node1},
      node2: %Node{first_public_key: node2}
      # node3: %Node{first_public_key: node3}
    } do
      # Should return intended nodes from setup
      assert [^node0, ^node2, ^node1] =
               Enum.map(Notifier.get_nodes_list(~U[2022-10-10 00:00:00Z]), & &1.first_public_key)

      assert [^node0] =
               Enum.map(Notifier.get_nodes_list(~U[2022-10-05 00:00:00Z]), & &1.first_public_key)
    end

    test "with_down_shard?/2", %{
      node0: %Node{first_public_key: node0},
      node1: %Node{first_public_key: node1},
      node2: %Node{first_public_key: node2},
      node3: %Node{first_public_key: node3}
    } do
      # prev shard must have unavailable node as to repair missing shard
      refute Notifier.with_down_shard?({"", [node0, node1, node2, node3]}, "node4")
      assert Notifier.with_down_shard?({"", [node0, node1, node2, node3]}, "node3")
    end

    test "current_node_in_node_list?/2",
         %{
           node0: %Node{first_public_key: node0},
           node1: %Node{first_public_key: node1},
           node2: %Node{first_public_key: node2},
           node3: %Node{first_public_key: node3}
         } do
      # prev shard must have unavailable node as to repair missing shard
      refute Notifier.current_node_in_node_list?({"", [node0, node1, node2, node3]}, "node4")

      assert Notifier.current_node_in_node_list?(
               {"", [node0, node1, node2, node3]},
               Crypto.first_node_public_key()
             )
    end

    test "new_storage_nodes/2", %{
      node0: %Node{first_public_key: node0},
      node1: %Node{first_public_key: node1},
      node2: %Node{first_public_key: node2},
      node3: %Node{first_public_key: node3}
    } do
      assert {"txn_addr", [^node2, ^node1]} =
               Notifier.new_storage_nodes({"txn_addr", [node0]}, node3)
    end

    test "map_node_and_address/2",
         %{
           node0: %Node{first_public_key: key0},
           node1: %Node{first_public_key: key1},
           node2: %Node{first_public_key: key2},
           node3: %Node{first_public_key: key3}
         } do
      assert %{
               ^key0 => "txn00",
               ^key1 => "txn00",
               ^key2 => "txn00",
               ^key3 => "txn00"
             } = acc = Notifier.map_node_and_address({"txn00", [key0, key1, key2, key3]}, %{})

      assert %{^key0 => "txn01", ^key1 => "txn01", ^key2 => "txn01", ^key3 => "txn01"} =
               Notifier.map_node_and_address({"txn01", [key0, key1, key2, key3]}, acc)

      assert [
               %{
                 ^key0 => "txn00",
                 ^key1 => "txn00",
                 ^key2 => "txn01",
                 ^key3 => "txn01"
               }
             ] =
               [{"txn00", [key0, key1, key2]}, {"txn01", [key2, key3]}]
               |> Stream.scan(%{}, &Notifier.map_node_and_address(&1, _acc = &2))
               |> Stream.take(-1)
               |> Enum.to_list()
    end

    test "notify_nodes/2", %{
      node0: %Node{first_public_key: key0},
      node1: %Node{first_public_key: key1},
      node2: %Node{first_public_key: key2},
      node3: %Node{first_public_key: key3}
    } do
      me = self()
      assert :ok = Notifier.notify_nodes([], "genesis_address")

      MockClient
      |> expect(:send_message, 4, fn
        %Node{first_public_key: ^key0}, %ShardRepair{last_address: "txn00"}, _ ->
          send(me, :msg_sent_for_node0)

        %Node{first_public_key: ^key1}, %ShardRepair{last_address: "txn00"}, _ ->
          send(me, :msg_sent_for_node1)

        %Node{first_public_key: ^key2}, %ShardRepair{last_address: "txn01"}, _ ->
          send(me, :msg_sent_for_node2)

        %Node{first_public_key: ^key3}, %ShardRepair{last_address: "txn01"}, _ ->
          send(me, :msg_sent_for_node3)
      end)

      assert :ok =
               Notifier.notify_nodes(
                 [
                   %{
                     key0 => "txn00",
                     key1 => "txn00",
                     key2 => "txn01",
                     key3 => "txn01"
                   }
                 ],
                 "genesis_address"
               )

      Enum.each(1..4, fn _x ->
        assert_receive msg

        assert msg in [
                 :msg_sent_for_node0,
                 :msg_sent_for_node1,
                 :msg_sent_for_node2,
                 :msg_sent_for_node3
               ]
      end)
    end

    def txn_chain(chain, type) do
      Enum.map(0..3, fn i ->
        %Transaction{
          address: chain <> "#{i}",
          validation_stamp: %Transaction.ValidationStamp{
            timestamp: DateTime.add(~U[2022-10-10 00:00:00Z], 86400 * i)
          },
          type: type
        }
      end)
    end

    # test "repair_transaction/2" do
    #   MockDB
    #   |> stub(:stream_genesis_addresses, fn ->
    #     ["txn_A_0", "txn_B_0", "txn_C_0"]
    #   end)

    #   MockCrypto
    #   |> stub(:last_public_key, fn ->
    #     "Node0 last_public_key"
    #   end)
    #   |> stub(:first_public_key, fn ->
    #     "Node0 first_public_key"
    #   end)
    #   |> stub(:previous_public_key, fn ->
    #     "Node0 previous_public_key"
    #   end)
    #   |> stub(:next_public_key, fn ->
    #     "Node0 next_public_key"
    #   end)

    #   # txn_list = txn_chain()

    #   txn0_address =
    #     List.first(txn_list).address
    #     |> tap(fn x -> IO.inspect(x, label: "00") end)

    #   MockDB
    #   |> stub(:get_transaction_chain, fn
    #     _, _, _ ->
    #       IO.inspect(label: "list tx")

    #       {txn_list, false, nil}
    #   end)

    #   P2P.add_and_connect_node(%Node{
    #     first_public_key: "node3",
    #     last_public_key: "node3",
    #     ip: {127, 0, 0, 1},
    #     port: 3001,
    #     available?: false,
    #     authorized?: true,
    #     authorization_date: ~U[2022-10-07 00:00:00Z],
    #     geo_patch: "CCC"
    #   })

    #   MockClient
    #   |> stub(:send_message, fn node, msg, timeout ->
    #     IO.inspect({node, msg, timeout}, label: " 9===mock client ")
    #   end)

    #   Notifier.sync_chain_by_chain(txn0_address, "node3", Crypto.first_node_public_key())
    #   Notifier.sync_chain_by_chain(txn0_address, "node3", "node1")
    #   Notifier.sync_chain_by_chain(txn0_address, "node3", "node2")
    #   Notifier.sync_chain_by_chain(txn0_address, "node3", "node3")
    #   Notifier.sync_chain_by_chain(txn0_address, "node3", "node4")
    #   Notifier.sync_chain_by_chain(txn0_address, "node3", "node5")
    # end
  end

  # test "when a node is becoming offline new nodes should receive transaction to replicate" do
  #   P2P.add_and_connect_node(%Node{
  #     first_public_key: Crypto.first_node_public_key(),
  #     last_public_key: Crypto.first_node_public_key(),
  #     ip: {127, 0, 0, 1},
  #     port: 3000,
  #     authorized?: true,
  #     authorization_date: ~U[2022-02-01 00:00:00Z],
  #     geo_patch: "AAA"
  #   })

  #   P2P.add_and_connect_node(%Node{
  #     first_public_key: "node2",
  #     last_public_key: "node2",
  #     ip: {127, 0, 0, 1},
  #     port: 3001,
  #     authorized?: true,
  #     authorization_date: ~U[2022-02-01 00:00:00Z],
  #     geo_patch: "CCC"
  #   })

  #   P2P.add_and_connect_node(%Node{
  #     first_public_key: "node3",
  #     last_public_key: "node3",
  #     ip: {127, 0, 0, 1},
  #     port: 3002,
  #     authorized?: true,
  #     authorization_date: ~U[2022-02-03 00:00:00Z],
  #     geo_patch: "DDD"
  #   })

  #   {:ok, pid} = Notifier.start_link()

  #   MockDB
  #   |> expect(:list_transactions, fn _ ->
  #     [
  #       %Transaction{
  #         address: "@Alice1",
  #         type: :transfer,
  #         validation_stamp: %ValidationStamp{
  #           timestamp: ~U[2022-02-01 12:54:00Z]
  #         }
  #       }
  #     ]
  #   end)

  #   me = self()

  #   MockClient
  #   |> expect(:send_message, fn %Node{first_public_key: "node3"},
  #                               %ReplicateTransaction{
  #                                 transaction: %Transaction{address: "@Alice1"}
  #                               },
  #                               _ ->
  #     send(me, :tx_replicated)
  #     %Ok{}
  #   end)

  #   send(
  #     pid,
  #     {:node_update,
  #      %Node{
  #        first_public_key: "node2",
  #        available?: false,
  #        authorized?: true,
  #        authorization_date: ~U[2022-02-01 00:00:00Z]
  #      }}
  #   )

  #   assert_receive :tx_replicated
  # end
end
