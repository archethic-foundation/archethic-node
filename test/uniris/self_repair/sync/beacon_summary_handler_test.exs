defmodule Uniris.SelfRepair.Sync.BeaconSummaryHandlerTest do
  use UnirisCase, async: false

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.Slot.EndOfNodeSync
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Uniris.BeaconChain.Subset, as: BeaconSubset
  alias Uniris.BeaconChain.Summary, as: BeaconSummary
  alias Uniris.BeaconChain.SummaryTimer, as: BeaconSummaryTimer

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetBeaconSummary
  alias Uniris.P2P.Message.GetTransaction
  alias Uniris.P2P.Message.GetTransactionChain
  alias Uniris.P2P.Message.GetTransactionInputs
  alias Uniris.P2P.Message.NotFound
  alias Uniris.P2P.Message.TransactionInputList
  alias Uniris.P2P.Message.TransactionList
  alias Uniris.P2P.Node

  alias Uniris.SharedSecrets.MemTables.NetworkLookup

  alias Uniris.SelfRepair.Sync.BeaconSummaryHandler
  alias Uniris.SelfRepair.Sync.BeaconSummaryHandler.NetworkStatistics

  alias Uniris.TransactionFactory

  alias Uniris.TransactionChain.TransactionInput

  import Mox

  setup do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(0),
      last_public_key: Crypto.node_public_key(0),
      network_patch: "AAA",
      geo_patch: "AAA"
    })

    Crypto.generate_deterministic_keypair("daily_nonce_seed")
    |> elem(0)
    |> NetworkLookup.set_daily_nonce_public_key(DateTime.utc_now())

    :ok
  end

  test "get_beacon_summaries/2" do
    node1 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key1",
      last_public_key: "key1",
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true,
      authorization_date: DateTime.utc_now(),
      authorized?: true
    }

    node2 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key2",
      last_public_key: "key2",
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true,
      authorization_date: DateTime.utc_now(),
      authorized?: true
    }

    node3 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key3",
      last_public_key: "key3",
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true,
      authorization_date: DateTime.utc_now(),
      authorized?: true
    }

    node4 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "node4",
      last_public_key: "node4",
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true,
      authorization_date: DateTime.utc_now(),
      authorized?: true
    }

    P2P.add_and_connect_node(node1)
    P2P.add_and_connect_node(node2)
    P2P.add_and_connect_node(node3)
    P2P.add_and_connect_node(node4)

    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.node_public_key(),
      network_patch: "AAA",
      available?: false
    })

    MockClient
    |> stub(:send_message, fn
      _, %GetBeaconSummary{subset: "D"} ->
        {:ok, %BeaconSummary{transaction_summaries: [%TransactionSummary{address: "@Alice3"}]}}

      _, %GetBeaconSummary{subset: "B"} ->
        {:ok, %BeaconSummary{transaction_summaries: [%TransactionSummary{address: "@Charlie5"}]}}

      _, %GetBeaconSummary{subset: "A"} ->
        {:ok, %BeaconSummary{transaction_summaries: [%TransactionSummary{address: "@Alice2"}]}}

      _, %GetBeaconSummary{subset: "F"} ->
        {:ok, %BeaconSummary{transaction_summaries: [%TransactionSummary{address: "@Tom2"}]}}

      _, %GetBeaconSummary{subset: "E"} ->
        {:ok, %BeaconSummary{transaction_summaries: [%TransactionSummary{address: "@Tom1"}]}}
    end)

    expected_addresses = [
      "@Alice2",
      "@Charlie5",
      "@Alice3",
      "@Tom1",
      "@Tom2"
    ]

    summary_pools = [
      {"A", [{~U[2021-01-22 16:12:58Z], [node1, node2]}]},
      {"B", [{~U[2021-01-22 16:12:58Z], [node1, node2]}]},
      {"D", [{~U[2021-01-22 16:12:58Z], [node1]}]},
      {"E", [{~U[2021-01-22 16:12:58Z], [node2, node1]}]},
      {"F", [{~U[2021-01-22 16:12:58Z], [node2]}]}
    ]

    transaction_addresses =
      summary_pools
      |> BeaconSummaryHandler.get_beacon_summaries("AAA")
      |> Enum.flat_map(& &1.transaction_summaries)
      |> Enum.map(& &1.address)

    assert Enum.all?(expected_addresses, &(&1 in transaction_addresses))
  end

  describe "handle_missing_summaries/2" do
    setup do
      start_supervised!({BeaconSlotTimer, [interval: "* * * * * *"]})
      start_supervised!({BeaconSummaryTimer, [interval: "0 * * * * *"]})
      :ok
    end

    test "should update P2P view with node synchronization ended" do
      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key",
        last_public_key: "key",
        geo_patch: "AAA",
        available?: true,
        authorization_date: DateTime.utc_now(),
        authorized?: true
      }

      P2P.add_and_connect_node(node)

      summaries = [
        %BeaconSummary{
          subset: <<0>>,
          summary_time: DateTime.utc_now(),
          end_of_node_synchronizations: [
            %EndOfNodeSync{
              public_key: "key"
            }
          ]
        }
      ]

      :ok = BeaconSummaryHandler.handle_missing_summaries(summaries, "AAA")
      {:ok, node} = P2P.get_node_info("key")
      assert true = Node.globally_available?(node)
    end

    test "should not synchronize transactions when not in the storage node pools" do
      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key",
        last_public_key: "key",
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorization_date: DateTime.utc_now(),
        authorized?: true
      }

      P2P.add_and_connect_node(node)

      me = self()

      inputs = [
        %TransactionInput{
          from: "@Alice2",
          amount: 10.0,
          type: :UCO,
          timestamp: DateTime.utc_now()
        }
      ]

      transfer_tx =
        TransactionFactory.create_valid_transaction(create_mining_context(), inputs,
          seed: "transfer_seed"
        )

      node_tx =
        TransactionFactory.create_valid_transaction(create_mining_context(), inputs,
          type: :node,
          seed: "node_seed",
          content: """
          ip: 127.0.0.1
          port: 3000
          transport: tcp
          reward address: 00E3F3E1F8E91CD72CF0AC899E89703E5745A5C2681628BE28C5D607B1EA25E82C
          """
        )

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{address: address} ->
          cond do
            address == transfer_tx.address ->
              send(me, :transaction_downloaded)
              {:ok, transfer_tx}

            address == node_tx.address ->
              send(me, :transaction_downloaded)
              {:ok, node_tx}

            true ->
              {:ok, %NotFound{}}
          end

        _, %GetTransactionChain{} ->
          {:ok, %TransactionList{transactions: []}}

        _, %GetTransactionInputs{} ->
          {:ok, %TransactionInputList{inputs: inputs}}
      end)

      summaries = [
        %BeaconSummary{
          subset: <<0>>,
          summary_time: DateTime.utc_now(),
          transaction_summaries: [
            %TransactionSummary{
              address: transfer_tx.address,
              type: :transfer,
              timestamp: transfer_tx.validation_stamp.timestamp
            }
          ]
        },
        %BeaconSummary{
          subset: <<1>>,
          summary_time: DateTime.utc_now(),
          transaction_summaries: [
            %TransactionSummary{
              address: node_tx.address,
              type: :node,
              timestamp: node_tx.validation_stamp.timestamp
            }
          ]
        }
      ]

      assert :ok = BeaconSummaryHandler.handle_missing_summaries(summaries, "AAA")
      assert 2 == NetworkStatistics.get_nb_transactions()
    end

    test "should synchronize transactions when the node is in the storage node pools" do
      Enum.each(BeaconChain.list_subsets(), &BeaconSubset.start_link(subset: &1))

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        last_address: :crypto.strong_rand_bytes(32),
        enrollment_date: DateTime.utc_now(),
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      }

      P2P.add_and_connect_node(node)

      inputs = [
        %TransactionInput{
          from: "@Alice2",
          amount: 10.0,
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
          amount: 10.0,
          type: :UCO,
          timestamp: DateTime.utc_now()
        }
      ]

      node_tx =
        TransactionFactory.create_valid_transaction(create_mining_context(), inputs,
          type: :node,
          seed: "node_seed",
          content: """
          ip: 127.0.0.1
          port: 3000
          transport: tcp
          reward address: 00E3F3E1F8E91CD72CF0AC899E89703E5745A5C2681628BE28C5D607B1EA25E82C
          """
        )

      summaries = [
        %BeaconSummary{
          subset: <<0>>,
          summary_time: DateTime.utc_now(),
          transaction_summaries: [
            %TransactionSummary{
              address: transfer_tx.address,
              type: :transfer,
              timestamp: DateTime.utc_now()
            }
          ]
        },
        %BeaconSummary{
          subset: <<0>>,
          summary_time: DateTime.utc_now(),
          transaction_summaries: [
            %TransactionSummary{
              address: node_tx.address,
              type: :node,
              timestamp: DateTime.utc_now()
            }
          ]
        }
      ]

      me = self()

      MockDB
      |> stub(:write_transaction_chain, fn _ ->
        send(me, :transaction_stored)
        :ok
      end)

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{address: address} ->
          cond do
            address == transfer_tx.address ->
              {:ok, transfer_tx}

            address == node_tx.address ->
              {:ok, node_tx}

            true ->
              {:ok, %NotFound{}}
          end

        _, %GetTransactionChain{} ->
          {:ok, %TransactionList{transactions: []}}

        _, %GetTransactionInputs{address: _} ->
          {:ok, %TransactionInputList{inputs: inputs}}
      end)

      assert :ok = BeaconSummaryHandler.handle_missing_summaries(summaries, "AAA")
      assert 2 == NetworkStatistics.get_nb_transactions()

      assert_received :transaction_stored
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
      last_address: :crypto.strong_rand_bytes(32),
      enrollment_date: DateTime.utc_now()
    }

    coordinator_node = %Node{
      first_public_key: Crypto.node_public_key(0),
      last_public_key: Crypto.node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA",
      last_address: :crypto.strong_rand_bytes(32),
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
        last_address: :crypto.strong_rand_bytes(32),
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
