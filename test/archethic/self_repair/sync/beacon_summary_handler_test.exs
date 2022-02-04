defmodule ArchEthic.SelfRepair.Sync.BeaconSummaryHandlerTest do
  use ArchEthicCase, async: false

  alias ArchEthic.BeaconChain.ReplicationAttestation
  alias ArchEthic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias ArchEthic.BeaconChain.Summary, as: BeaconSummary
  alias ArchEthic.BeaconChain.SummaryTimer, as: BeaconSummaryTimer

  alias ArchEthic.Crypto

  alias ArchEthic.Election

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.GetBeaconSummary
  alias ArchEthic.P2P.Message.GetTransaction
  alias ArchEthic.P2P.Message.GetTransactionChain
  alias ArchEthic.P2P.Message.GetTransactionInputs
  alias ArchEthic.P2P.Message.GetUnspentOutputs
  alias ArchEthic.P2P.Message.TransactionInputList
  alias ArchEthic.P2P.Message.TransactionList
  alias ArchEthic.P2P.Message.UnspentOutputList
  alias ArchEthic.P2P.Node

  alias ArchEthic.SharedSecrets.MemTables.NetworkLookup

  alias ArchEthic.SelfRepair.Sync.BeaconSummaryHandler
  alias ArchEthic.SelfRepair.Sync.BeaconSummaryAggregate

  alias ArchEthic.TransactionFactory

  alias ArchEthic.TransactionChain.TransactionInput
  alias ArchEthic.TransactionChain.TransactionSummary

  import Mox

  setup do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.first_node_public_key(),
      network_patch: "AAA",
      geo_patch: "AAA",
      reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    })

    Crypto.generate_deterministic_keypair("daily_nonce_seed")
    |> elem(0)
    |> NetworkLookup.set_daily_nonce_public_key(DateTime.utc_now() |> DateTime.add(-10))

    ArchEthic.SelfRepair.Scheduler.start_link(interval: "0 0 0 * * *")

    :ok
  end

  describe "get_full_beacon_summary/3" do
    setup do
      summary_time = ~U[2021-01-22 16:12:58Z]

      node_keypair1 = Crypto.derive_keypair("node_seed", 1)
      node_keypair2 = Crypto.derive_keypair("node_seed", 2)
      node_keypair3 = Crypto.derive_keypair("node_seed", 3)
      node_keypair4 = Crypto.derive_keypair("node_seed", 4)

      node1 = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: elem(node_keypair1, 0),
        last_public_key: elem(node_keypair1, 0),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorization_date: summary_time |> DateTime.add(-10),
        authorized?: true,
        reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
      }

      node2 = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: elem(node_keypair2, 0),
        last_public_key: elem(node_keypair2, 0),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorization_date: summary_time |> DateTime.add(-10),
        authorized?: true,
        reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
      }

      node3 = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: elem(node_keypair3, 0),
        last_public_key: elem(node_keypair3, 0),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorization_date: summary_time |> DateTime.add(-10),
        authorized?: true,
        reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
      }

      node4 = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: elem(node_keypair4, 0),
        last_public_key: elem(node_keypair4, 0),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorization_date: summary_time |> DateTime.add(-10),
        authorized?: true,
        reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
      }

      P2P.add_and_connect_node(node1)
      P2P.add_and_connect_node(node2)
      P2P.add_and_connect_node(node3)
      P2P.add_and_connect_node(node4)

      P2P.add_and_connect_node(%Node{
        first_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        available?: false
      })

      {:ok, %{summary_time: summary_time, nodes: [node1, node2, node3, node4]}}
    end

    test "should download the beacon summary", %{
      summary_time: summary_time,
      nodes: [node1, node2, node3, node4]
    } do
      addr1 = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

      beacon_summary_address_a = Crypto.derive_beacon_chain_address("A", summary_time, true)

      tx_summary = %TransactionSummary{
        address: addr1,
        timestamp: DateTime.utc_now(),
        type: :transfer
      }

      storage_nodes =
        Election.chain_storage_nodes_with_type(addr1, :transfer, P2P.available_nodes())

      beacon_summary = %BeaconSummary{
        subset: "A",
        summary_time: summary_time,
        transaction_attestations: [
          %ReplicationAttestation{
            transaction_summary: tx_summary,
            confirmations:
              [node1, node2, node3, node4]
              |> Enum.with_index(1)
              |> Enum.map(fn {node, index} ->
                node_index = Enum.find_index(storage_nodes, &(&1 == node))
                {_, pv} = Crypto.derive_keypair("node_seed", index)
                {node_index, Crypto.sign(TransactionSummary.serialize(tx_summary), pv)}
              end)
          }
        ]
      }

      MockClient
      |> stub(:send_message, fn
        _, %GetBeaconSummary{address: ^beacon_summary_address_a}, _ ->
          {:ok, beacon_summary}
      end)

      %BeaconSummary{transaction_attestations: transaction_attestations} =
        BeaconSummaryHandler.get_full_beacon_summary(summary_time, "A", [
          node1,
          node2,
          node3,
          node4
        ])

      assert [addr1] == Enum.map(transaction_attestations, & &1.transaction_summary.address)
    end

    test "should find other beacon summaries and aggregate missing summaries", %{
      summary_time: summary_time,
      nodes: [node1, node2, _, _]
    } do
      addr1 = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
      addr2 = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

      summary_v1 = %BeaconSummary{
        subset: "A",
        summary_time: summary_time,
        transaction_attestations: [
          %ReplicationAttestation{
            transaction_summary: %TransactionSummary{
              address: addr1,
              timestamp: DateTime.utc_now(),
              type: :transfer
            }
          }
        ]
      }

      summary_v2 = %BeaconSummary{
        subset: "A",
        summary_time: summary_time,
        transaction_attestations: [
          %ReplicationAttestation{
            transaction_summary: %TransactionSummary{
              address: addr1,
              timestamp: DateTime.utc_now(),
              type: :transfer
            }
          },
          %ReplicationAttestation{
            transaction_summary: %TransactionSummary{
              address: addr2,
              timestamp: DateTime.utc_now(),
              type: :transfer
            }
          }
        ]
      }

      MockClient
      |> stub(:send_message, fn
        ^node1, %GetBeaconSummary{}, _ ->
          {:ok, summary_v1}

        ^node2, %GetBeaconSummary{}, _ ->
          {:ok, summary_v2}
      end)

      %BeaconSummary{transaction_attestations: transaction_attestations} =
        BeaconSummaryHandler.get_full_beacon_summary(summary_time, "A", [node1, node2])

      transaction_addresses = Enum.map(transaction_attestations, & &1.address)

      assert Enum.all?(transaction_addresses, &(&1 in [addr1, addr2]))
    end

    test "should find other beacon summaries and aggregate node P2P views", %{
      summary_time: summary_time,
      nodes: [node1, node2, node3, node4]
    } do
      summary_v1 = %BeaconSummary{
        subset: "A",
        summary_time: summary_time,
        node_availabilities: <<1::1, 1::1, 0::1>>
      }

      summary_v2 = %BeaconSummary{
        subset: "A",
        summary_time: summary_time,
        node_availabilities: <<1::1, 1::1, 1::1>>
      }

      summary_v3 = %BeaconSummary{
        subset: "A",
        summary_time: summary_time,
        node_availabilities: <<1::1, 0::1, 1::1>>
      }

      summary_v4 = %BeaconSummary{
        subset: "A",
        summary_time: summary_time,
        node_availabilities: <<1::1, 1::1, 0::1>>
      }

      MockClient
      |> stub(:send_message, fn
        ^node1, %GetBeaconSummary{}, _ ->
          {:ok, summary_v1}

        ^node2, %GetBeaconSummary{}, _ ->
          {:ok, summary_v2}

        ^node3, %GetBeaconSummary{}, _ ->
          {:ok, summary_v3}

        ^node4, %GetBeaconSummary{}, _ ->
          {:ok, summary_v4}
      end)

      assert %BeaconSummary{node_availabilities: <<1::1, 1::1, 1::1>>} =
               BeaconSummaryHandler.get_full_beacon_summary(summary_time, "A", [
                 node1,
                 node2,
                 node3,
                 node4
               ])
    end

    test "should find other beacon summaries and aggregate node P2P avg availabilities", %{
      summary_time: summary_time,
      nodes: [node1, node2, node3, node4]
    } do
      summary_v1 = %BeaconSummary{
        subset: "A",
        summary_time: summary_time,
        node_average_availabilities: [1.0, 0.9, 1.0, 1.0]
      }

      summary_v2 = %BeaconSummary{
        subset: "A",
        summary_time: summary_time,
        node_average_availabilities: [0.90, 0.9, 1.0, 1.0]
      }

      summary_v3 = %BeaconSummary{
        subset: "A",
        summary_time: summary_time,
        node_average_availabilities: [0.8, 0.9, 0.7, 1.0]
      }

      summary_v4 = %BeaconSummary{
        subset: "A",
        summary_time: summary_time,
        node_availabilities: <<1::1, 1::1, 0::1>>,
        node_average_availabilities: [1, 0.5, 1, 0.4]
      }

      MockClient
      |> stub(:send_message, fn
        ^node1, %GetBeaconSummary{}, _ ->
          {:ok, summary_v1}

        ^node2, %GetBeaconSummary{}, _ ->
          {:ok, summary_v2}

        ^node3, %GetBeaconSummary{}, _ ->
          {:ok, summary_v3}

        ^node4, %GetBeaconSummary{}, _ ->
          {:ok, summary_v4}
      end)

      assert %BeaconSummary{node_average_availabilities: [0.925, 0.8, 0.925, 0.85]} =
               BeaconSummaryHandler.get_full_beacon_summary(summary_time, "A", [
                 node1,
                 node2,
                 node3,
                 node4
               ])
    end
  end

  describe "process_summary_aggregate/2" do
    setup do
      start_supervised!({BeaconSlotTimer, [interval: "* * * * * *"]})
      start_supervised!({BeaconSummaryTimer, [interval: "0 * * * * *"]})
      :ok
    end

    test "should synchronize transactions" do
      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        reward_address: :crypto.strong_rand_bytes(32),
        enrollment_date: DateTime.utc_now(),
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      }

      P2P.add_and_connect_node(node)

      inputs = [
        %TransactionInput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now()
        }
      ]

      transfer_tx =
        TransactionFactory.create_valid_transaction(create_mining_context(), inputs,
          seed: "transfer_seed"
        )

      inputs = [
        %TransactionInput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now()
        }
      ]

      tx_address = transfer_tx.address

      me = self()

      MockDB
      |> stub(:write_transaction_chain, fn _ ->
        send(me, :transaction_stored)
        :ok
      end)

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{address: ^tx_address}, _ ->
          {:ok, transfer_tx}

        _, %GetTransactionChain{}, _ ->
          {:ok, %TransactionList{transactions: []}}

        _, %GetTransactionInputs{address: _}, _ ->
          {:ok, %TransactionInputList{inputs: inputs}}

        _, %GetUnspentOutputs{}, _ ->
          {:ok, %UnspentOutputList{unspent_outputs: inputs}}
      end)

      MockDB
      |> stub(:register_tps, fn _, _, _ ->
        :ok
      end)

      assert :ok =
               BeaconSummaryHandler.process_summary_aggregate(
                 %BeaconSummaryAggregate{
                   summary_time: DateTime.utc_now(),
                   transaction_summaries: [
                     %TransactionSummary{
                       address: tx_address,
                       type: :transfer,
                       timestamp: DateTime.utc_now()
                     }
                   ]
                 },
                 "AAA"
               )

      assert_received :transaction_stored
    end
  end

  defp create_mining_context do
    welcome_node = %Node{
      first_public_key: "key1",
      last_public_key: "key1",
      available?: true,
      geo_patch: "BBB",
      network_patch: "BBB",
      reward_address: :crypto.strong_rand_bytes(32),
      enrollment_date: DateTime.utc_now()
    }

    coordinator_node = %Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA",
      reward_address: :crypto.strong_rand_bytes(32),
      enrollment_date: DateTime.utc_now()
    }

    storage_nodes = [
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key3",
        last_public_key: "key3",
        available?: true,
        geo_patch: "BBB",
        network_patch: "BBB",
        reward_address: :crypto.strong_rand_bytes(32),
        authorization_date: DateTime.utc_now(),
        authorized?: true
      }
    ]

    Enum.each(storage_nodes, &P2P.add_and_connect_node(&1))

    P2P.add_and_connect_node(welcome_node)
    P2P.add_and_connect_node(coordinator_node)

    %{
      welcome_node: welcome_node,
      coordinator_node: coordinator_node,
      storage_nodes: storage_nodes
    }
  end
end
