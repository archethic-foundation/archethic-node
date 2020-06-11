defmodule UnirisCore.SelfRepairTest do
  use UnirisCoreCase, async: false

  alias UnirisCore.SelfRepair
  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.LedgerMovements
  alias UnirisCore.Transaction.ValidationStamp.NodeMovements
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.BeaconSlot
  alias UnirisCore.BeaconSlot.TransactionInfo
  alias UnirisCore.Crypto
  alias UnirisCore.Mining.ProofOfIntegrity

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    start_supervised!(UnirisCore.Storage.Cache)
    start_supervised!({UnirisCore.BeaconSlotTimer, slot_interval: 10_000})
    pid = start_supervised!({SelfRepair, interval: 10_000})
    {:ok, %{pid: pid}}
  end

  test "start_sync/2 starts the repair mechanism and download missing transactions" do
    me = self()

    tx_alice1 = %Transaction{
      address: Crypto.hash("@Alice1"),
      timestamp: DateTime.utc_now(),
      type: :transfer,
      data: %{},
      previous_public_key: "@Alice0",
      previous_signature: "",
      origin_signature: ""
    }

    tx_alice1 = %{
      tx_alice1
      | validation_stamp: %ValidationStamp{
          proof_of_integrity: ProofOfIntegrity.compute([tx_alice1]),
          proof_of_work: :crypto.strong_rand_bytes(32),
          ledger_movements: %LedgerMovements{},
          node_movements: %NodeMovements{fee: 0.0, rewards: []},
          signature: ""
        }
    }

    tx_alice2 = %Transaction{
      address: Crypto.hash("@Alice2"),
      timestamp: DateTime.utc_now(),
      type: :transfer,
      data: %{},
      previous_public_key: "@Alice1",
      previous_signature: "",
      origin_signature: ""
    }

    tx_alice2 = %{
      tx_alice2
      | validation_stamp: %ValidationStamp{
          proof_of_integrity: ProofOfIntegrity.compute([tx_alice2, tx_alice1]),
          proof_of_work: :crypto.strong_rand_bytes(32),
          ledger_movements: %LedgerMovements{},
          node_movements: %NodeMovements{fee: 0.0, rewards: []},
          signature: ""
        }
    }

    tx_node1 = %Transaction{
      address: Crypto.hash("@Node1"),
      timestamp: DateTime.utc_now(),
      type: :node,
      data: %{},
      previous_public_key: "@Node0",
      previous_signature: "",
      origin_signature: ""
    }

    tx_node1 = %{
      tx_node1
      | validation_stamp: %ValidationStamp{
          proof_of_integrity: ProofOfIntegrity.compute([tx_node1]),
          proof_of_work: :crypto.strong_rand_bytes(32),
          ledger_movements: %LedgerMovements{},
          node_movements: %NodeMovements{fee: 0.0, rewards: []},
          signature: ""
        }
    }

    MockStorage
    |> stub(:write_transaction_chain, fn chain ->
      send(me, chain)
      :ok
    end)
    |> stub(:get_transaction_chain, fn address ->
      cond do
        address == Crypto.hash("@Alice1") ->
          {:ok, [tx_alice1]}

        true ->
          {:error, :transaction_chain_not_exists}
      end
    end)

    MockNodeClient
    |> stub(:send_message, fn _, _, msg ->
      case msg do
        {:get_beacon_slots, _slots} ->
          [
            %BeaconSlot{
              transactions: [
                %TransactionInfo{
                  address: "@Alice2",
                  type: :transfer,
                  timestamp: DateTime.utc_now() |> DateTime.add(2)
                }
              ]
            },
            %BeaconSlot{
              transactions: [
                %TransactionInfo{
                  address: "@Alice1",
                  type: :transfer,
                  timestamp: DateTime.utc_now()
                },
                %TransactionInfo{
                  address: "@Node1",
                  type: :node,
                  timestamp: DateTime.utc_now()
                }
              ]
            }
          ]

        {:get_transaction, address} ->
          case address do
            "@Alice1" ->
              {:ok, tx_alice1}

            "@Alice2" ->
              {:ok, tx_alice2}

            "@Node1" ->
              {:ok, tx_node1}
          end
      end
    end)

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: Crypto.node_public_key(0),
      first_public_key: Crypto.node_public_key(0),
      network_patch: "AAA",
      geo_patch: "AAA",
      ready?: true,
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-60),
      enrollment_date: DateTime.utc_now() |> DateTime.add(-60)
    })

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: :crypto.strong_rand_bytes(32),
      first_public_key: :crypto.strong_rand_bytes(32),
      network_patch: "AAA",
      geo_patch: "AAA",
      ready?: true,
      available?: true,
      enrollment_date: DateTime.utc_now() |> DateTime.add(-60)
    })

    SelfRepair.start_sync("AAA")
    Process.sleep(500)

    assert_received [%Transaction{type: :node, previous_public_key: "@Node0"}], 500

    assert_received [%Transaction{type: :transfer, previous_public_key: "@Alice0"}], 500

    assert_received [
                      %Transaction{type: :transfer, previous_public_key: "@Alice1"},
                      %Transaction{type: :transfer, previous_public_key: "@Alice0"}
                    ],
                    500
  end
end
