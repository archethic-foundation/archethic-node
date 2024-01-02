defmodule Archethic.BeaconChain.Slot.ValidationTest do
  use ArchethicCase

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Slot.EndOfNodeSync
  alias Archethic.BeaconChain.Slot.Validation, as: SlotValidation

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.TransactionFactory

  import Mock

  describe "valid_transaction_attestations?/1" do
    setup_with_mocks([
      {ReplicationAttestation, [],
       validate: fn %ReplicationAttestation{transaction_summary: %TransactionSummary{type: type}} ->
         if type == :transfer, do: :ok, else: {:error, :invalid_confirmations_signatures}
       end}
    ]) do
      :ok
    end

    test "should return true if all attestation are valid" do
      tx1 = TransactionFactory.create_valid_transaction([], seed: "abc")
      tx1_summary = TransactionSummary.from_transaction(tx1, Transaction.previous_address(tx1))

      tx2 = TransactionFactory.create_valid_transaction([], seed: "123")
      tx2_summary = TransactionSummary.from_transaction(tx2, Transaction.previous_address(tx2))

      attestation1 = %ReplicationAttestation{transaction_summary: tx1_summary, confirmations: []}
      attestation2 = %ReplicationAttestation{transaction_summary: tx2_summary, confirmations: []}

      slot = %Slot{transaction_attestations: [attestation1, attestation2]}

      assert SlotValidation.valid_transaction_attestations?(slot)
    end

    test "should return false if at least one attestation is invalid" do
      tx1 = TransactionFactory.create_valid_transaction([], seed: "abc")
      tx1_summary = TransactionSummary.from_transaction(tx1, Transaction.previous_address(tx1))

      tx2 = TransactionFactory.create_valid_transaction([], seed: "123", type: :node)
      tx2_summary = TransactionSummary.from_transaction(tx2, Transaction.previous_address(tx2))

      attestation1 = %ReplicationAttestation{transaction_summary: tx1_summary, confirmations: []}
      attestation2 = %ReplicationAttestation{transaction_summary: tx2_summary, confirmations: []}

      slot = %Slot{transaction_attestations: [attestation1, attestation2]}

      refute SlotValidation.valid_transaction_attestations?(slot)
    end
  end

  describe "valid_end_of_node_sync?/1" do
    setup do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        geo_patch: "AAA",
        network_patch: "AAA"
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key2",
        last_public_key: "key2",
        geo_patch: "AAA",
        network_patch: "AAA"
      })
    end

    test "should return true if node exists" do
      slot = %Slot{
        end_of_node_synchronizations: [
          %EndOfNodeSync{public_key: "key1", timestamp: DateTime.utc_now()},
          %EndOfNodeSync{public_key: "key2", timestamp: DateTime.utc_now()}
        ]
      }

      assert SlotValidation.valid_end_of_node_sync?(slot)
    end

    test "should return false if at least one node doesn't exist" do
      slot = %Slot{
        end_of_node_synchronizations: [
          %EndOfNodeSync{public_key: "key1", timestamp: DateTime.utc_now()},
          %EndOfNodeSync{public_key: "key3", timestamp: DateTime.utc_now()}
        ]
      }

      refute SlotValidation.valid_end_of_node_sync?(slot)
    end
  end

  describe "valid_p2p_view?/1" do
    setup do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: <<0::24, :crypto.strong_rand_bytes(31)::binary>>,
        last_public_key: <<0::24, :crypto.strong_rand_bytes(31)::binary>>,
        geo_patch: "AAA",
        network_patch: "AAA"
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: <<0::24, :crypto.strong_rand_bytes(31)::binary>>,
        last_public_key: <<0::24, :crypto.strong_rand_bytes(31)::binary>>,
        geo_patch: "AAA",
        network_patch: "AAA"
      })
    end

    test "should return true if p2p view length correspond to node subset" do
      slot = %Slot{
        subset: <<0>>,
        p2p_view: %{
          availabilities: <<600::16, 600::16>>,
          network_stats: [%{latency: 10}, %{latency: 10}]
        }
      }

      assert SlotValidation.valid_p2p_view?(slot)
    end

    test "should return false if p2p view length does not correspond to node subset" do
      slot = %Slot{
        subset: <<0>>,
        p2p_view: %{
          availabilities: <<600::16>>,
          network_stats: [%{latency: 10}]
        }
      }

      refute SlotValidation.valid_p2p_view?(slot)
    end
  end
end
