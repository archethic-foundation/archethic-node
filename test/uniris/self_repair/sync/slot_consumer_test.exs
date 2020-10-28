defmodule Uniris.SelfRepair.Sync.SlotConsumerTest do
  use UnirisCase

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.Slot, as: BeaconSlot
  alias Uniris.BeaconChain.Slot.NodeInfo
  alias Uniris.BeaconChain.Slot.TransactionInfo
  alias Uniris.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Uniris.BeaconChain.Subset, as: BeaconSubset

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetTransaction
  alias Uniris.P2P.Message.GetTransactionChain
  alias Uniris.P2P.Message.GetTransactionInputs
  alias Uniris.P2P.Message.TransactionInputList
  alias Uniris.P2P.Message.TransactionList
  alias Uniris.P2P.Node

  alias Uniris.SelfRepair.Sync.SlotConsumer

  alias Uniris.TransactionFactory

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionInput

  import Mox

  describe "handle_missing_slots/2" do
    test "should update P2P view with node readiness" do
      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key",
        last_public_key: "key"
      }

      P2P.add_node(node)

      slots = [
        %BeaconSlot{
          nodes: [
            %NodeInfo{
              public_key: "key",
              ready?: true
            }
          ]
        }
      ]

      :ok = SlotConsumer.handle_missing_slots(slots, "AAA")
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

      slots = [
        %BeaconSlot{
          transactions: [
            %TransactionInfo{
              address: "@Alice2",
              type: :transfer,
              timestamp: DateTime.utc_now()
            }
          ]
        },
        %BeaconSlot{
          transactions: [
            %TransactionInfo{
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

      assert :ok = SlotConsumer.handle_missing_slots(slots, "AAA")
    end

    test "should synchronize transactions when the node is in the storage node pools" do
      start_supervised!({BeaconSlotTimer, [interval: "* * * * * *", trigger_offset: 0]})
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

      inputs = [%TransactionInput{from: "@Alice2", amount: 10.0}]

      transfer_tx =
        TransactionFactory.create_valid_transaction(create_mining_context(), inputs,
          seed: "transfer_seed"
        )

      inputs = [%TransactionInput{from: "@Alice2", amount: 10.0}]

      node_tx =
        TransactionFactory.create_valid_transaction(create_mining_context(), inputs,
          type: :node,
          seed: "node_seed",
          content: """
          ip: 127.0.0.1
          port: 3000
          """
        )

      slots = [
        %BeaconSlot{
          transactions: [
            %TransactionInfo{
              address: transfer_tx.address,
              type: :transfer,
              timestamp: DateTime.utc_now()
            }
          ]
        },
        %BeaconSlot{
          transactions: [
            %TransactionInfo{
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

      assert :ok = SlotConsumer.handle_missing_slots(slots, "AAA")

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
