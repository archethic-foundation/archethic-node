defmodule Archethic.P2p.Message.CurrentReplicationAttestationsTest do
  @moduledoc false
  use ExUnit.Case
  import ArchethicCase

  alias Archethic.P2P.Message.CurrentReplicationAttestations
  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.TransactionChain.TransactionSummary

  test "serialization/deserialization" do
    msg = %CurrentReplicationAttestations{
      replication_attestations: [
        %ReplicationAttestation{
          transaction_summary: %TransactionSummary{
            address: random_address(),
            type: :transfer,
            timestamp: ~U[2022-01-27 09:14:22.000Z],
            fee: 10_000_000,
            validation_stamp_checksum: :crypto.strong_rand_bytes(32),
            genesis_address: random_address()
          },
          confirmations: Enum.map(0..9, &{&1, "signature#{&1}"})
        },
        %ReplicationAttestation{
          transaction_summary: %TransactionSummary{
            address: random_address(),
            type: :transfer,
            timestamp: ~U[2022-01-27 09:14:23.000Z],
            fee: 10_000_000,
            validation_stamp_checksum: :crypto.strong_rand_bytes(32),
            genesis_address: random_address()
          },
          confirmations: Enum.map(0..9, &{&1, "signature#{&1}"})
        }
      ]
    }

    assert {^msg, <<>>} =
             msg
             |> CurrentReplicationAttestations.serialize()
             |> CurrentReplicationAttestations.deserialize()

    msg = %CurrentReplicationAttestations{
      replication_attestations: []
    }

    assert {^msg, <<>>} =
             msg
             |> CurrentReplicationAttestations.serialize()
             |> CurrentReplicationAttestations.deserialize()
  end
end
