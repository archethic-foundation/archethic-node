defmodule Archethic.SelfRepair.NotifierTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.{
    Crypto,
    P2P,
    P2P.Node,
    SelfRepair.Notifier,
    TransactionChain,
    TransactionChain.Transaction,
    TransactionFactory
  }

  alias Archethic.P2P.Message.{Ok, ShardRepair}

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
      assert [^node1, ^node2, ^node0] =
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

    # test "current_node_in_node_list?/2",
    #      %{
    #        node0: %Node{first_public_key: node0},
    #        node1: %Node{first_public_key: node1},
    #        node2: %Node{first_public_key: node2},
    #        node3: %Node{first_public_key: node3}
    #      } do
    #   # prev shard must have unavailable node as to repair missing shard
    #   refute Notifier.current_node_in_node_list?({"", [node0, node1, node2, node3]}, "node4")

    #   assert Notifier.current_node_in_node_list?(
    #            {"", [node0, node1, node2, node3]},
    #            Crypto.first_node_public_key()
    #          )
    # end

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
      assert :ok = Notifier.notify_nodes([], "first_address")

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
                 "first_address"
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
            timestamp: DateTime.add(~U[2022-10-10 00:00:00Z], 86_400 * i)
          },
          type: type
        }
      end)
    end
  end

  describe "when a node is becoming offline new nodes should receive transaction to replicate" do
    setup do
      P2P.add_and_connect_node(%Node{
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        ip: {127, 0, 0, 1},
        port: 3000,
        authorized?: true,
        authorization_date: ~U[2022-10-05 00:00:00Z],
        geo_patch: "AAA"
      })

      P2P.add_and_connect_node(%Node{
        first_public_key: "node2",
        last_public_key: "node2",
        ip: {127, 0, 0, 1},
        port: 3001,
        authorized?: true,
        authorization_date: ~U[2022-10-10 00:00:00Z],
        geo_patch: "CCC"
      })

      P2P.add_and_connect_node(%Node{
        first_public_key: "node3",
        last_public_key: "node3",
        ip: {127, 0, 0, 1},
        port: 3002,
        authorized?: true,
        authorization_date: ~U[2022-10-15 00:00:00Z],
        geo_patch: "DDD"
      })

      chain_a = build_chain("chain_a", 3)
      chain_b = build_chain("chain_b", 3)
      first_txn_address_a = Map.get(chain_a, 0).address
      last_addr_a = Map.get(chain_a, 2).address
      last_addr_b = Map.get(chain_b, 2).address
      first_txn_address_b = Map.get(chain_b, 0).address

      [net_txn0] = network_txns()

      net_chain_gen_addr = net_txn0.address

      %{
        chain_a: chain_a,
        chain_b: chain_b,
        first_txn_address_a: first_txn_address_a,
        first_txn_address_b: first_txn_address_b,
        net_chain_gen_addr: net_chain_gen_addr,
        net_txn0: net_txn0,
        last_addr_a: last_addr_a,
        last_addr_b: last_addr_b
      }
    end

    test "sync_chain/1 Manual piping Asserts", %{
      chain_a: chain_a,
      first_txn_address_a: first_txn_address_a,
      last_addr_a: last_addr_a
    } do
      P2P.add_and_connect_node(%Node{
        first_public_key: "node4",
        last_public_key: "node4",
        ip: {127, 0, 0, 1},
        port: 3002,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "DDD"
      })

      P2P.add_and_connect_node(%Node{
        first_public_key: "node5",
        last_public_key: "node5",
        ip: {127, 0, 0, 1},
        port: 3002,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "DDD"
      })

      txn_chain_a = [Map.get(chain_a, 0), Map.get(chain_a, 1), Map.get(chain_a, 2)]

      MockDB
      |> stub(:get_transaction_chain, fn
        ^first_txn_address_a, [:address, validation_stamp: [:timestamp]], _ ->
          {txn_chain_a, false, nil}
      end)

      me = self()

      MockClient
      |> stub(
        :send_message,
        fn
          %Node{first_public_key: "node4"},
          %ShardRepair{
            first_address: ^first_txn_address_a,
            last_address: ^last_addr_a
          },
          _ ->
            send(me, :msg_sent_to_node_4)
            %Ok{}

          %Node{first_public_key: "node5"},
          %ShardRepair{
            first_address: ^first_txn_address_a,
            last_address: ^last_addr_a
          },
          _ ->
            send(me, :msg_sent_to_node_5)
            %Ok{}
        end
      )

      current_node_public_key = Crypto.first_node_public_key()
      unavailable_node_key = "node2"
      first_address = first_txn_address_a

      result =
        first_address
        |> TransactionChain.stream([:address, validation_stamp: [:timestamp]])
        |> Enum.to_list()
        |> tap(fn x ->
          assert txn_chain_a == x
        end)
        |> Enum.map(&Notifier.list_previous_shards(&1))
        |> tap(fn x ->
          assert [
                   {<<0, 0, 173, 101, 18, 205, 43, 59, 180, 93, 83, 18, 213, 205, 199, 213, 145,
                      76, 251, 44, 60, 191, 122, 82, 118, 247, 170, 144, 49, 2, 31, 141, 191,
                      67>>,
                    [
                      <<1, 1, 4, 77, 145, 160, 161, 167, 207, 6, 162, 144, 45, 56, 66, 248, 45,
                        39, 145, 188, 191, 62, 230, 246, 220, 141, 224, 249, 14, 83, 233, 153, 28,
                        60, 179, 54, 132, 183, 185, 230, 111, 38, 231, 201, 245, 48, 47, 115, 198,
                        152, 151, 190, 95, 48, 29, 233, 166, 53, 33, 160, 138, 196, 239, 52, 193,
                        135, 40>>,
                      "node3",
                      "node2"
                    ]},
                   {<<0, 0, 191, 175, 21, 41, 199, 29, 33, 216, 13, 129, 218, 110, 143, 148, 82,
                      173, 188, 239, 203, 60, 186, 152, 111, 42, 234, 36, 68, 140, 34, 100, 13,
                      89>>,
                    [
                      <<1, 1, 4, 77, 145, 160, 161, 167, 207, 6, 162, 144, 45, 56, 66, 248, 45,
                        39, 145, 188, 191, 62, 230, 246, 220, 141, 224, 249, 14, 83, 233, 153, 28,
                        60, 179, 54, 132, 183, 185, 230, 111, 38, 231, 201, 245, 48, 47, 115, 198,
                        152, 151, 190, 95, 48, 29, 233, 166, 53, 33, 160, 138, 196, 239, 52, 193,
                        135, 40>>,
                      "node2",
                      "node3"
                    ]},
                   {<<0, 0, 192, 250, 30, 251, 248, 152, 199, 106, 223, 237, 137, 176, 214, 135,
                      207, 197, 158, 98, 51, 235, 230, 141, 47, 130, 95, 158, 173, 46, 124, 92,
                      173, 199>>,
                    [
                      "node2",
                      "node3",
                      <<1, 1, 4, 77, 145, 160, 161, 167, 207, 6, 162, 144, 45, 56, 66, 248, 45,
                        39, 145, 188, 191, 62, 230, 246, 220, 141, 224, 249, 14, 83, 233, 153, 28,
                        60, 179, 54, 132, 183, 185, 230, 111, 38, 231, 201, 245, 48, 47, 115, 198,
                        152, 151, 190, 95, 48, 29, 233, 166, 53, 33, 160, 138, 196, 239, 52, 193,
                        135, 40>>
                    ]}
                 ] == x
        end)
        |> Enum.filter(&Notifier.with_down_shard?(&1, unavailable_node_key))
        |> tap(fn x ->
          assert x ==
                   [
                     {<<0, 0, 173, 101, 18, 205, 43, 59, 180, 93, 83, 18, 213, 205, 199, 213, 145,
                        76, 251, 44, 60, 191, 122, 82, 118, 247, 170, 144, 49, 2, 31, 141, 191,
                        67>>,
                      [
                        <<1, 1, 4, 77, 145, 160, 161, 167, 207, 6, 162, 144, 45, 56, 66, 248, 45,
                          39, 145, 188, 191, 62, 230, 246, 220, 141, 224, 249, 14, 83, 233, 153,
                          28, 60, 179, 54, 132, 183, 185, 230, 111, 38, 231, 201, 245, 48, 47,
                          115, 198, 152, 151, 190, 95, 48, 29, 233, 166, 53, 33, 160, 138, 196,
                          239, 52, 193, 135, 40>>,
                        "node3",
                        "node2"
                      ]},
                     {<<0, 0, 191, 175, 21, 41, 199, 29, 33, 216, 13, 129, 218, 110, 143, 148, 82,
                        173, 188, 239, 203, 60, 186, 152, 111, 42, 234, 36, 68, 140, 34, 100, 13,
                        89>>,
                      [
                        <<1, 1, 4, 77, 145, 160, 161, 167, 207, 6, 162, 144, 45, 56, 66, 248, 45,
                          39, 145, 188, 191, 62, 230, 246, 220, 141, 224, 249, 14, 83, 233, 153,
                          28, 60, 179, 54, 132, 183, 185, 230, 111, 38, 231, 201, 245, 48, 47,
                          115, 198, 152, 151, 190, 95, 48, 29, 233, 166, 53, 33, 160, 138, 196,
                          239, 52, 193, 135, 40>>,
                        "node2",
                        "node3"
                      ]},
                     {<<0, 0, 192, 250, 30, 251, 248, 152, 199, 106, 223, 237, 137, 176, 214, 135,
                        207, 197, 158, 98, 51, 235, 230, 141, 47, 130, 95, 158, 173, 46, 124, 92,
                        173, 199>>,
                      [
                        "node2",
                        "node3",
                        <<1, 1, 4, 77, 145, 160, 161, 167, 207, 6, 162, 144, 45, 56, 66, 248, 45,
                          39, 145, 188, 191, 62, 230, 246, 220, 141, 224, 249, 14, 83, 233, 153,
                          28, 60, 179, 54, 132, 183, 185, 230, 111, 38, 231, 201, 245, 48, 47,
                          115, 198, 152, 151, 190, 95, 48, 29, 233, 166, 53, 33, 160, 138, 196,
                          239, 52, 193, 135, 40>>
                      ]}
                   ]
        end)
        |> Enum.map(&Notifier.new_storage_nodes(&1, unavailable_node_key))
        |> tap(fn x ->
          assert x == [
                   {<<0, 0, 173, 101, 18, 205, 43, 59, 180, 93, 83, 18, 213, 205, 199, 213, 145,
                      76, 251, 44, 60, 191, 122, 82, 118, 247, 170, 144, 49, 2, 31, 141, 191,
                      67>>, ["node4", "node5"]},
                   {<<0, 0, 191, 175, 21, 41, 199, 29, 33, 216, 13, 129, 218, 110, 143, 148, 82,
                      173, 188, 239, 203, 60, 186, 152, 111, 42, 234, 36, 68, 140, 34, 100, 13,
                      89>>, ["node4", "node5"]},
                   {<<0, 0, 192, 250, 30, 251, 248, 152, 199, 106, 223, 237, 137, 176, 214, 135,
                      207, 197, 158, 98, 51, 235, 230, 141, 47, 130, 95, 158, 173, 46, 124, 92,
                      173, 199>>, ["node5", "node4"]}
                 ]
        end)
        |> Stream.scan(%{}, &Notifier.map_node_and_address(&1, _acc = &2))
        |> Enum.to_list()
        |> tap(fn x ->
          assert x == [
                   %{
                     "node4" =>
                       <<0, 0, 173, 101, 18, 205, 43, 59, 180, 93, 83, 18, 213, 205, 199, 213,
                         145, 76, 251, 44, 60, 191, 122, 82, 118, 247, 170, 144, 49, 2, 31, 141,
                         191, 67>>,
                     "node5" =>
                       <<0, 0, 173, 101, 18, 205, 43, 59, 180, 93, 83, 18, 213, 205, 199, 213,
                         145, 76, 251, 44, 60, 191, 122, 82, 118, 247, 170, 144, 49, 2, 31, 141,
                         191, 67>>
                   },
                   %{
                     "node4" =>
                       <<0, 0, 191, 175, 21, 41, 199, 29, 33, 216, 13, 129, 218, 110, 143, 148,
                         82, 173, 188, 239, 203, 60, 186, 152, 111, 42, 234, 36, 68, 140, 34, 100,
                         13, 89>>,
                     "node5" =>
                       <<0, 0, 191, 175, 21, 41, 199, 29, 33, 216, 13, 129, 218, 110, 143, 148,
                         82, 173, 188, 239, 203, 60, 186, 152, 111, 42, 234, 36, 68, 140, 34, 100,
                         13, 89>>
                   },
                   %{
                     "node4" =>
                       <<0, 0, 192, 250, 30, 251, 248, 152, 199, 106, 223, 237, 137, 176, 214,
                         135, 207, 197, 158, 98, 51, 235, 230, 141, 47, 130, 95, 158, 173, 46,
                         124, 92, 173, 199>>,
                     "node5" =>
                       <<0, 0, 192, 250, 30, 251, 248, 152, 199, 106, 223, 237, 137, 176, 214,
                         135, 207, 197, 158, 98, 51, 235, 230, 141, 47, 130, 95, 158, 173, 46,
                         124, 92, 173, 199>>
                   }
                 ]
        end)
        |> Stream.take(-1)
        |> Enum.take(1)
        |> tap(fn x ->
          assert x == [
                   %{
                     "node4" =>
                       <<0, 0, 192, 250, 30, 251, 248, 152, 199, 106, 223, 237, 137, 176, 214,
                         135, 207, 197, 158, 98, 51, 235, 230, 141, 47, 130, 95, 158, 173, 46,
                         124, 92, 173, 199>>,
                     "node5" =>
                       <<0, 0, 192, 250, 30, 251, 248, 152, 199, 106, 223, 237, 137, 176, 214,
                         135, 207, 197, 158, 98, 51, 235, 230, 141, 47, 130, 95, 158, 173, 46,
                         124, 92, 173, 199>>
                   }
                 ]
        end)

      assert result ==
               first_address
               |> TransactionChain.stream([:address, validation_stamp: [:timestamp]])
               |> Stream.map(&Notifier.list_previous_shards(&1))
               |> Stream.filter(&Notifier.with_down_shard?(&1, unavailable_node_key))
               #  |> Stream.filter(&Notifier.current_node_in_node_list?(&1, current_node_public_key))
               |> Stream.map(&Notifier.new_storage_nodes(&1, unavailable_node_key))
               |> Stream.scan(%{}, &Notifier.map_node_and_address(&1, _acc = &2))
               |> Stream.take(-1)
               |> Enum.take(1)
    end

    test "Integeration Test", %{
      chain_a: chain_a,
      chain_b: chain_b,
      first_txn_address_a: first_txn_address_a,
      first_txn_address_b: first_txn_address_b,
      net_chain_gen_addr: net_chain_gen_addr,
      last_addr_a: last_addr_a,
      last_addr_b: last_addr_b,
      net_txn0: net_txn0
    } do
      # new node
      P2P.add_and_connect_node(%Node{
        first_public_key: "node4",
        last_public_key: "node4",
        ip: {127, 0, 0, 1},
        port: 3002,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "DDD"
      })

      Notifier.start_link()

      MockDB
      |> stub(:get_transaction_chain, fn
        ^first_txn_address_a, [:address, validation_stamp: [:timestamp]], _ ->
          {[Map.get(chain_a, 0), Map.get(chain_a, 1), Map.get(chain_a, 2)], false, nil}

        ^first_txn_address_b, [:address, validation_stamp: [:timestamp]], _ ->
          {[Map.get(chain_b, 0), Map.get(chain_b, 1), Map.get(chain_b, 2)], false, nil}
      end)
      |> stub(:stream_first_addresses, fn ->
        [first_txn_address_a, net_chain_gen_addr, first_txn_address_b]
      end)
      |> stub(:get_transaction, fn
        ^net_chain_gen_addr, [:type] ->
          {:ok, net_txn0}

        ^first_txn_address_a, [:type] ->
          {:ok, Map.get(chain_a, 0)}

        ^first_txn_address_b, [:type] ->
          {:ok, Map.get(chain_b, 0)}
      end)

      me = self()

      MockClient
      |> stub(
        :send_message,
        fn
          %Node{first_public_key: "node4"},
          %ShardRepair{
            first_address: ^first_txn_address_a,
            last_address: ^last_addr_a
          },
          _ ->
            send(me, :msg_sent_A)
            %Ok{}

          %Node{first_public_key: "node4"},
          %ShardRepair{
            first_address: ^first_txn_address_b,
            last_address: ^last_addr_b
          },
          _ ->
            send(me, :msg_sent_B)
            %Ok{}
        end
      )

      P2P.set_node_globally_unavailable("node2")
      # send node2 is down

      assert_receive :msg_sent_A
      assert_receive :msg_sent_B
    end

    def build_chain(seed, length \\ 1) when length > 0 do
      alias Archethic.TransactionFactory

      time = DateTime.utc_now() |> DateTime.add(-5000 * length)

      Enum.reduce(0..(length - 1), _acc = {_map = %{}, _prev_tx = []}, fn
        index, {map, prev_tx} ->
          # put input un mock client
          txn =
            TransactionFactory.create_valid_chain(
              [],
              seed: seed,
              index: index,
              prev_txn: prev_tx,
              timestamp: time |> DateTime.add(5000 * index)
            )

          {
            Map.put(map, index, txn),
            [txn]
          }
      end)
      |> elem(0)
    end

    def network_txns do
      curr_time = DateTime.utc_now()

      txn0 =
        TransactionFactory.create_network_tx(:node_shared_secrets,
          index: 0,
          timestamp: curr_time |> DateTime.add(-14_400, :second),
          prev_txn: []
        )

      [txn0]
    end
  end
end
