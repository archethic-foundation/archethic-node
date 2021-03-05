defmodule Uniris.BeaconChain.Subset.SlotConsensusTest do
  use UnirisCase, async: false

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.SlotTimer
  alias Uniris.BeaconChain.Subset.SlotConsensus
  alias Uniris.BeaconChain.SummaryTimer

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Batcher
  alias Uniris.P2P.Message.AddBeaconSlotProof
  alias Uniris.P2P.Message.BatchRequests
  alias Uniris.P2P.Message.BatchResponses
  alias Uniris.P2P.Message.NotifyBeaconSlot
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Node

  alias Uniris.Utils

  import Mox

  setup do
    start_supervised!({SlotTimer, interval: "0 * * * * *"})
    start_supervised!({SummaryTimer, interval: "0 0 * * * *"})
    start_supervised!(Batcher)

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(),
      last_public_key: Crypto.node_public_key(),
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA"
    })

    P2P.add_node(%Node{
      ip: {59, 23, 123, 10},
      port: 3005,
      first_public_key: Crypto.node_public_key(1),
      last_public_key: Crypto.node_public_key(1),
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA"
    })

    P2P.add_node(%Node{
      ip: {120, 200, 10, 23},
      port: 3005,
      first_public_key: Crypto.node_public_key(2),
      last_public_key: Crypto.node_public_key(2),
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA"
    })

    :ok
  end

  test "start_link/1 should start a slot consensus worker and start the validation process" do
    {:ok, pid} =
      SlotConsensus.start_link(
        node_public_key: Crypto.node_public_key(0),
        slot: %Slot{
          subset: <<0>>,
          slot_time: DateTime.utc_now(),
          transaction_summaries: [
            %TransactionSummary{
              address: :crypto.strong_rand_bytes(32),
              timestamp: DateTime.utc_now(),
              type: :transfer
            }
          ]
        }
      )

    MockClient
    |> stub(:send_message, fn _, %BatchRequests{requests: [%AddBeaconSlotProof{}]}, _ ->
      {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}
    end)

    assert {:waiting_proofs, _} = :sys.get_state(pid)
  end

  describe "add_slot_proof/2" do
    test "should reject a proof which is not cryptographically valid" do
      slot = %Slot{
        subset: <<0>>,
        slot_time: DateTime.utc_now(),
        transaction_summaries: [
          %TransactionSummary{
            address: :crypto.strong_rand_bytes(32),
            timestamp: DateTime.utc_now(),
            type: :transfer
          }
        ]
      }

      MockClient
      |> stub(:send_message, fn _, %BatchRequests{requests: [%AddBeaconSlotProof{}]}, _ ->
        {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}
      end)

      {:ok, pid} =
        SlotConsensus.start_link(node_public_key: Crypto.node_public_key(0), slot: slot)

      assert {:error, :invalid_proof} =
               SlotConsensus.add_slot_proof(
                 pid,
                 Slot.digest(slot),
                 <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
                 :crypto.strong_rand_bytes(64)
               )
    end

    test "should accept the proof and wait to receive enough proofs" do
      slot = %Slot{
        subset: <<0>>,
        slot_time: DateTime.utc_now(),
        transaction_summaries: [
          %TransactionSummary{
            address: :crypto.strong_rand_bytes(32),
            timestamp: DateTime.utc_now(),
            type: :transfer
          }
        ]
      }

      {:ok, pid} =
        SlotConsensus.start_link(
          node_public_key: Crypto.node_public_key(0),
          slot: slot,
          timeout: 10_000
        )

      MockClient
      |> stub(:send_message, fn
        _, %BatchRequests{requests: [%AddBeaconSlotProof{}]}, _ ->
          {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}

        _, %BatchRequests{requests: [%NotifyBeaconSlot{}]}, _ ->
          {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}
      end)

      assert :ok =
               SlotConsensus.add_slot_proof(
                 pid,
                 Slot.digest(slot),
                 Crypto.node_public_key(1),
                 Crypto.sign_with_node_key(Slot.digest(slot), 1)
               )

      assert {:waiting_proofs,
              %{
                current_slot: %Slot{
                  involved_nodes: involved_nodes,
                  validation_signatures: validation_signatures
                }
              }} = :sys.get_state(pid)

      assert 2 == Utils.count_bitstring_bits(involved_nodes)
      assert 2 == map_size(validation_signatures)
    end

    test "should notify the summary pool when enough valid signatures has been gathered" do
      slot = %Slot{
        subset: <<0>>,
        slot_time: DateTime.utc_now(),
        transaction_summaries: [
          %TransactionSummary{
            address: :crypto.strong_rand_bytes(32),
            timestamp: DateTime.utc_now(),
            type: :transfer
          }
        ]
      }

      me = self()

      MockClient
      |> stub(:send_message, fn
        _, %BatchRequests{requests: [%AddBeaconSlotProof{}]}, _ ->
          {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}

        _, %BatchRequests{requests: [%NotifyBeaconSlot{}]}, _ ->
          send(me, :slot_sent)
          {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}

        _, %BatchRequests{requests: [%NotifyBeaconSlot{}, %AddBeaconSlotProof{}]}, _ ->
          {:ok, %BatchResponses{responses: [{0, %Ok{}}, {1, %Ok{}}]}}

        _,
        %BatchRequests{
          requests: [%NotifyBeaconSlot{}, %AddBeaconSlotProof{}, %AddBeaconSlotProof{}]
        },
        _ ->
          {:ok, %BatchResponses{responses: [{0, %Ok{}}, {1, %Ok{}}, {2, %Ok{}}]}}
      end)

      {:ok, pid} =
        SlotConsensus.start_link(
          node_public_key: Crypto.node_public_key(0),
          slot: slot,
          timeout: 10_000
        )

      assert :ok =
               SlotConsensus.add_slot_proof(
                 pid,
                 Slot.digest(slot),
                 Crypto.node_public_key(1),
                 Crypto.sign_with_node_key(Slot.digest(slot), 1)
               )

      assert :ok =
               SlotConsensus.add_slot_proof(
                 pid,
                 Slot.digest(slot),
                 Crypto.node_public_key(2),
                 Crypto.sign_with_node_key(Slot.digest(slot), 2)
               )

      assert_receive :slot_sent, 3_000
    end
  end
end
