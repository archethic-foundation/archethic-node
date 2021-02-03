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
  alias Uniris.P2P.Message.TransactionInputList
  alias Uniris.P2P.Message.TransactionList
  alias Uniris.P2P.Node

  alias Uniris.SelfRepair.Sync.BeaconSummaryHandler
  alias Uniris.SelfRepair.Sync.BeaconSummaryHandler.NetworkStatistics

  alias Uniris.TransactionFactory

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  import Mox

  test "get_beacon_summaries/2" do
    node1 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key1",
      last_public_key: "key1",
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true
    }

    node2 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key2",
      last_public_key: "key2",
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true
    }

    node3 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key3",
      last_public_key: "key3",
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true
    }

    node4 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "node4",
      last_public_key: "node4",
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true
    }

    P2P.add_node(node1)
    P2P.add_node(node2)
    P2P.add_node(node3)
    P2P.add_node(node4)

    MockTransport
    |> stub(:send_message, fn
      _, _, %GetBeaconSummary{subset: "A"} ->
        {:ok, %BeaconSummary{transaction_summaries: [%TransactionSummary{address: "@Alice2"}]}}

      _, _, %GetBeaconSummary{subset: "B"} ->
        {:ok, %BeaconSummary{transaction_summaries: [%TransactionSummary{address: "@Charlie5"}]}}

      _, _, %GetBeaconSummary{subset: "D"} ->
        {:ok, %BeaconSummary{transaction_summaries: [%TransactionSummary{address: "@Alice3"}]}}

      _, _, %GetBeaconSummary{subset: "E"} ->
        {:ok, %BeaconSummary{transaction_summaries: [%TransactionSummary{address: "@Tom1"}]}}

      _, _, %GetBeaconSummary{subset: "F"} ->
        {:ok, %BeaconSummary{transaction_summaries: [%TransactionSummary{address: "@Tom2"}]}}
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
        available?: true
      }

      P2P.add_node(node)

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
        network_patch: "AAA"
      }

      P2P.add_node(node)

      summaries = [
        %BeaconSummary{
          subset: <<0>>,
          summary_time: DateTime.utc_now(),
          transaction_summaries: [
            %TransactionSummary{
              address: "@Alice2",
              type: :transfer,
              timestamp: DateTime.utc_now()
            }
          ]
        },
        %BeaconSummary{
          subset: <<1>>,
          summary_time: DateTime.utc_now(),
          transaction_summaries: [
            %TransactionSummary{
              address: "@Node10",
              type: :node,
              timestamp: DateTime.utc_now()
            }
          ]
        }
      ]

      me = self()

      MockTransport
      |> stub(:send_message, fn
        _, _, %GetTransaction{address: "@Alice2"} ->
          send(me, :transaction_downloaded)
          {:ok, %Transaction{}}

        _, _, %GetTransaction{address: "@Node1"} ->
          send(me, :transaction_downloaded)
          {:ok, %Transaction{}}
      end)

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
        network_patch: "AAA"
      }

      P2P.add_node(node)

      inputs = [%UnspentOutput{from: "@Alice2", amount: 10.0, type: :UCO}]

      transfer_tx =
        TransactionFactory.create_valid_transaction(create_mining_context(), inputs,
          seed: "transfer_seed"
        )

      inputs = [%UnspentOutput{from: "@Alice2", amount: 10.0, type: :UCO}]

      node_tx =
        TransactionFactory.create_valid_transaction(create_mining_context(), inputs,
          type: :node,
          seed: "node_seed",
          content: """
          ip: 127.0.0.1
          port: 3000
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

      MockTransport
      |> stub(:send_message, fn
        _, _, %GetTransaction{address: address} ->
          cond do
            address == transfer_tx.address ->
              {:ok, transfer_tx}

            address == node_tx.address ->
              {:ok, node_tx}

            true ->
              raise "Oops!"
          end

        _, _, %GetTransactionInputs{} ->
          {:ok, %TransactionInputList{inputs: inputs}}

        _, _, %GetTransactionChain{} ->
          {:ok, %TransactionList{transactions: []}}
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
      network_patch: "BBB"
    }

    coordinator_node = %Node{
      first_public_key: Crypto.node_public_key(0),
      last_public_key: Crypto.node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA"
    }

    storage_nodes = [
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key3",
        last_public_key: "key3",
        available?: true,
        geo_patch: "BBB",
        network_patch: "BBB"
      }
    ]

    Enum.each(storage_nodes, &P2P.add_node(&1))

    P2P.add_node(welcome_node)
    P2P.add_node(coordinator_node)

    %{
      welcome_node: welcome_node,
      coordinator_node: coordinator_node,
      storage_nodes: storage_nodes
    }
  end
end
