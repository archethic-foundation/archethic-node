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
  alias Uniris.P2P.Message.GetTransaction
  alias Uniris.P2P.Message.GetTransactionChain
  alias Uniris.P2P.Message.GetTransactionInputs
  alias Uniris.P2P.Message.NotFound
  alias Uniris.P2P.Message.TransactionInputList
  alias Uniris.P2P.Message.TransactionList
  alias Uniris.P2P.Node

  alias Uniris.SharedSecrets.MemTables.NetworkLookup

  alias Uniris.SelfRepair.Sync.BeaconSummaryHandler

  alias Uniris.TransactionFactory

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionInput

  alias Uniris.Utils

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
      authorized?: true,
      reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
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
      authorized?: true,
      reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
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
      authorized?: true,
      reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
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

    summary_time = ~U[2021-01-22 16:12:58Z]

    addr1 = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    addr2 = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    addr3 = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    addr4 = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    addr5 = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

    MockClient
    |> stub(:send_message, fn
      _, %GetTransaction{address: address} ->
        cond do
          address == Crypto.derive_beacon_chain_address("D", summary_time, true) ->
            {:ok,
             %Transaction{
               address: address,
               type: :beacon_summary,
               data: %TransactionData{
                 content:
                   %BeaconSummary{
                     subset: "D",
                     summary_time: summary_time,
                     transaction_summaries: [
                       %TransactionSummary{
                         address: addr1,
                         timestamp: DateTime.utc_now(),
                         type: :transfer
                       }
                     ]
                   }
                   |> BeaconSummary.serialize()
                   |> Utils.wrap_binary()
               }
             }}

          address == Crypto.derive_beacon_chain_address("B", summary_time, true) ->
            {:ok,
             %Transaction{
               address: address,
               type: :beacon_summary,
               data: %TransactionData{
                 content:
                   %BeaconSummary{
                     subset: "B",
                     summary_time: summary_time,
                     transaction_summaries: [
                       %TransactionSummary{
                         address: addr2,
                         timestamp: DateTime.utc_now(),
                         type: :transfer
                       }
                     ]
                   }
                   |> BeaconSummary.serialize()
                   |> Utils.wrap_binary()
               }
             }}

          address == Crypto.derive_beacon_chain_address("A", summary_time, true) ->
            {:ok,
             %Transaction{
               address: address,
               type: :beacon_summary,
               data: %TransactionData{
                 content:
                   %BeaconSummary{
                     subset: "A",
                     summary_time: summary_time,
                     transaction_summaries: [
                       %TransactionSummary{
                         address: addr3,
                         timestamp: DateTime.utc_now(),
                         type: :transfer
                       }
                     ]
                   }
                   |> BeaconSummary.serialize()
                   |> Utils.wrap_binary()
               }
             }}

          address == Crypto.derive_beacon_chain_address("F", summary_time, true) ->
            {:ok,
             %Transaction{
               address: address,
               type: :beacon_summary,
               data: %TransactionData{
                 content:
                   %BeaconSummary{
                     subset: "F",
                     summary_time: summary_time,
                     transaction_summaries: [
                       %TransactionSummary{
                         address: addr4,
                         timestamp: DateTime.utc_now(),
                         type: :transfer
                       }
                     ]
                   }
                   |> BeaconSummary.serialize()
                   |> Utils.wrap_binary()
               }
             }}

          address == Crypto.derive_beacon_chain_address("E", summary_time, true) ->
            {:ok,
             %Transaction{
               address: address,
               type: :beacon_summary,
               data: %TransactionData{
                 content:
                   %BeaconSummary{
                     subset: "E",
                     summary_time: summary_time,
                     transaction_summaries: [
                       %TransactionSummary{
                         address: addr5,
                         timestamp: DateTime.utc_now(),
                         type: :transfer
                       }
                     ]
                   }
                   |> BeaconSummary.serialize()
                   |> Utils.wrap_binary()
               }
             }}

          true ->
            raise "Error"
        end
    end)

    expected_addresses = [
      addr1,
      addr2,
      addr3,
      addr4,
      addr5
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
        authorized?: true,
        reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
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

      MockDB
      |> stub(:register_tps, fn _, _, _ -> :ok end)

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
        authorized?: true,
        reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
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
          content:
            <<127, 0, 0, 1, 3000::16, 1, 0, :crypto.strong_rand_bytes(32)::binary, 64::16,
              :crypto.strong_rand_bytes(64)::binary>>
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

      MockDB
      |> stub(:register_tps, fn _, _, _ -> :ok end)

      assert :ok = BeaconSummaryHandler.handle_missing_summaries(summaries, "AAA")
    end

    test "should synchronize transactions when the node is in the storage node pools" do
      Enum.each(BeaconChain.list_subsets(), &BeaconSubset.start_link(subset: &1))

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
          content:
            <<127, 0, 0, 1, 3000::16, 1, 0::8, :crypto.strong_rand_bytes(32)::binary, 64::16,
              :crypto.strong_rand_bytes(64)::binary>>
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

      MockDB
      |> stub(:register_tps, fn _, _, _ ->
        :ok
      end)

      assert :ok = BeaconSummaryHandler.handle_missing_summaries(summaries, "AAA")

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
