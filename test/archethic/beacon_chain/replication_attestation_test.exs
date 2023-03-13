defmodule Archethic.BeaconChain.ReplicationAttestationTest do
  use ArchethicCase

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.SummaryTimer

  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.P2P
  alias Archethic.P2P.Node

  doctest ReplicationAttestation

  describe "reached_threshold?/1" do
    setup do
      # Summary timer each hour
      start_supervised!({SummaryTimer, interval: "0 0 * * * *"})
      # Create 10 nodes on last summary
      Enum.each(0..9, fn i ->
        P2P.add_and_connect_node(%Node{
          ip: {88, 130, 19, i},
          port: 3000 + i,
          last_public_key: :crypto.strong_rand_bytes(32),
          first_public_key: :crypto.strong_rand_bytes(32),
          geo_patch: "AAA",
          available?: true,
          authorized?: true,
          authorization_date: DateTime.utc_now() |> DateTime.add(-1, :hour),
          enrollment_date: DateTime.utc_now() |> DateTime.add(-2, :hour)
        })
      end)

      # Add two node in the current summary
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: :crypto.strong_rand_bytes(32),
        first_public_key: :crypto.strong_rand_bytes(32),
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        enrollment_date: DateTime.utc_now()
      })

      # Add two node in the current summary
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 2},
        port: 3001,
        last_public_key: :crypto.strong_rand_bytes(32),
        first_public_key: :crypto.strong_rand_bytes(32),
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        enrollment_date: DateTime.utc_now()
      })
    end

    test "should return true if attestation reached threshold" do
      # First Replication with enough threshold
      attestation = %ReplicationAttestation{
        transaction_summary: %TransactionSummary{
          timestamp: DateTime.utc_now() |> DateTime.add(-1, :hour)
        },
        confirmations: Enum.map(0..9, &{&1, "signature#{&1}"})
      }

      assert ReplicationAttestation.reached_threshold?(attestation)

      # Second Replication without enough threshold
      attestation = %ReplicationAttestation{
        transaction_summary: %TransactionSummary{
          timestamp: DateTime.utc_now() |> DateTime.add(-1, :hour)
        },
        confirmations: Enum.map(0..2, &{&1, "signature#{&1}"})
      }

      assert ReplicationAttestation.reached_threshold?(attestation)
    end

    test "should return false if attestation do not reach threshold" do
      # First Replication with enough threshold
      attestation = %ReplicationAttestation{
        transaction_summary: %TransactionSummary{
          timestamp: DateTime.utc_now()
        },
        confirmations: Enum.map(0..9, &{&1, "signature#{&1}"})
      }

      assert ReplicationAttestation.reached_threshold?(attestation)

      # Second Replication without enough threshold
      attestation = %ReplicationAttestation{
        transaction_summary: %TransactionSummary{
          timestamp: DateTime.utc_now()
        },
        confirmations: Enum.map(0..2, &{&1, "signature#{&1}"})
      }

      refute ReplicationAttestation.reached_threshold?(attestation)
    end
  end
end
