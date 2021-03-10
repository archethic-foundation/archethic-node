defmodule Uniris.BeaconChain.SubsetTest do
  use UnirisCase, async: false

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.EndOfNodeSync
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.SlotTimer
  alias Uniris.BeaconChain.Summary
  alias Uniris.BeaconChain.SummaryTimer

  alias Uniris.BeaconChain.Subset

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Batcher
  alias Uniris.P2P.Message.AddBeaconSlotProof
  alias Uniris.P2P.Message.BatchRequests
  alias Uniris.P2P.Message.BatchResponses
  alias Uniris.P2P.Message.GetBeaconSlot
  alias Uniris.P2P.Message.NotFound
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Node

  alias Uniris.Utils

  import Mox

  setup do
    pid = start_supervised!({Subset, subset: <<0>>})
    start_supervised!({SummaryTimer, interval: "0 0 * * * *"})
    start_supervised!({SlotTimer, interval: "0 * * * * *"})
    start_supervised!(Batcher)
    {:ok, subset: <<0>>, pid: pid}
  end

  test "add_transaction_summary/2 should publish a transaction into the next beacon block", %{
    subset: subset,
    pid: pid
  } do
    tx_time = DateTime.utc_now()
    tx_address = :crypto.strong_rand_bytes(32)

    Subset.add_transaction_summary(subset, %TransactionSummary{
      address: tx_address,
      timestamp: tx_time,
      type: :node
    })

    assert %{
             current_slot: %Slot{
               transaction_summaries: [%TransactionSummary{address: ^tx_address}]
             }
           } = :sys.get_state(pid)
  end

  test "add_end_of_node_sync/2 should insert end of node synchronization in the beacon slot", %{
    subset: subset,
    pid: pid
  } do
    public_key = :crypto.strong_rand_bytes(32)

    :ok = Subset.add_end_of_node_sync(subset, %EndOfNodeSync{public_key: public_key})

    assert %{
             current_slot: %Slot{
               end_of_node_synchronizations: [%EndOfNodeSync{public_key: ^public_key}]
             }
           } = :sys.get_state(pid)
  end

  test "new slot is created when receive a :create_slot message", %{subset: subset, pid: pid} do
    tx_time = DateTime.utc_now()
    tx_address = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(0),
      last_public_key: Crypto.node_public_key(0),
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      enrollment_date: DateTime.utc_now()
    })

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(1),
      last_public_key: Crypto.node_public_key(1),
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      enrollment_date: DateTime.utc_now()
    })

    Subset.add_transaction_summary(subset, %TransactionSummary{
      address: tx_address,
      timestamp: tx_time,
      type: :keychain,
      movements_addresses: [
        <<0, 109, 2, 63, 124, 238, 101, 213, 214, 64, 58, 218, 10, 35, 62, 202, 12, 64, 11, 232,
          210, 105, 102, 193, 193, 24, 54, 42, 200, 226, 13, 38, 69>>,
        <<0, 8, 253, 201, 142, 182, 78, 169, 132, 29, 19, 74, 3, 142, 207, 219, 127, 147, 40, 24,
          44, 170, 214, 171, 224, 29, 177, 205, 226, 88, 62, 248, 84>>
      ]
    })

    public_key = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    ready_time = DateTime.utc_now()

    Subset.add_end_of_node_sync(subset, %EndOfNodeSync{
      public_key: public_key,
      timestamp: ready_time
    })

    MockClient
    |> stub(:send_message, fn
      _, %BatchRequests{requests: [%GetBeaconSlot{}]}, _ ->
        {:ok, %BatchResponses{responses: [{0, %NotFound{}}]}}

      _, %BatchRequests{requests: [%AddBeaconSlotProof{}]}, _ ->
        {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}
    end)

    send(pid, {:create_slot, DateTime.utc_now()})

    Process.sleep(200)

    %{consensus_worker: consensus_pid} = :sys.get_state(pid)

    assert {:waiting_proofs,
            %{
              current_slot: %Slot{
                transaction_summaries: [%TransactionSummary{address: ^tx_address}],
                end_of_node_synchronizations: [%EndOfNodeSync{public_key: ^public_key}]
              }
            }} = :sys.get_state(consensus_pid)
  end

  test "add_slot_proof/2 should add beacon slot proof to the consensus worker", %{
    subset: subset,
    pid: pid
  } do
    tx_time = DateTime.utc_now()
    tx_address = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(),
      last_public_key: Crypto.node_public_key(),
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      enrollment_date: DateTime.utc_now()
    })

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(1),
      last_public_key: Crypto.node_public_key(1),
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      enrollment_date: DateTime.utc_now()
    })

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(2),
      last_public_key: Crypto.node_public_key(2),
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      enrollment_date: DateTime.utc_now()
    })

    tx_summary = %TransactionSummary{
      address: tx_address,
      timestamp: tx_time,
      type: :keychain,
      movements_addresses: [
        <<0, 109, 2, 63, 124, 238, 101, 213, 214, 64, 58, 218, 10, 35, 62, 202, 12, 64, 11, 232,
          210, 105, 102, 193, 193, 24, 54, 42, 200, 226, 13, 38, 69>>,
        <<0, 8, 253, 201, 142, 182, 78, 169, 132, 29, 19, 74, 3, 142, 207, 219, 127, 147, 40, 24,
          44, 170, 214, 171, 224, 29, 177, 205, 226, 88, 62, 248, 84>>
      ]
    }

    Subset.add_transaction_summary(subset, tx_summary)

    slot_time = DateTime.utc_now()
    send(pid, {:create_slot, slot_time})

    MockClient
    |> stub(:send_message, fn
      _, %BatchRequests{requests: [%GetBeaconSlot{}]}, _ ->
        {:ok, %BatchResponses{responses: [{0, %NotFound{}}]}}

      _, %BatchRequests{requests: [%AddBeaconSlotProof{}]}, _ ->
        {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}
    end)

    slot_digest =
      %Slot{subset: subset, slot_time: slot_time, transaction_summaries: [tx_summary]}
      |> Slot.digest()

    :ok =
      Subset.add_slot_proof(
        subset,
        slot_digest,
        Crypto.node_public_key(1),
        Crypto.sign_with_node_key(slot_digest, 1)
      )

    %{consensus_worker: consensus_pid} = :sys.get_state(pid)

    assert {_,
            %{
              current_slot: %Slot{
                involved_nodes: involved_nodes,
                validation_signatures: signatures
              }
            }} = :sys.get_state(consensus_pid)

    assert 2 == map_size(signatures)
    assert 2 == Utils.count_bitstring_bits(involved_nodes)
  end

  test "new summary is created when receive a :create_summary message", %{pid: pid} do
    me = self()

    MockDB
    |> expect(:register_beacon_summary, fn summary ->
      send(me, {:summary, summary})
      :ok
    end)
    |> expect(:get_beacon_slots, fn _, _ ->
      [
        %Slot{
          transaction_summaries: [
            %TransactionSummary{
              address: "@Alice2",
              type: :transfer,
              timestamp: ~U[2021-01-22 09:01:56Z]
            }
          ]
        },
        %Slot{
          transaction_summaries: [
            %TransactionSummary{
              address: "@Bob3",
              type: :transfer,
              timestamp: ~U[2021-01-22 08:50:22Z]
            }
          ],
          end_of_node_synchronizations: [
            %EndOfNodeSync{
              public_key: "NodeKey1",
              timestamp: ~U[2021-01-22 08:53:18Z]
            }
          ]
        }
      ]
    end)

    summary_time = DateTime.utc_now()
    send(pid, {:create_summary, summary_time})

    assert_receive {:summary,
                    %Summary{
                      subset: <<0>>,
                      summary_time: ^summary_time,
                      transaction_summaries: [
                        %TransactionSummary{address: "@Bob3"},
                        %TransactionSummary{address: "@Alice2"}
                      ],
                      end_of_node_synchronizations: [
                        %EndOfNodeSync{public_key: "NodeKey1"}
                      ]
                    }}
  end
end
