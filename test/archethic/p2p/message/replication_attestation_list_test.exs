defmodule Archethic.P2p.Message.ReplicationAttestationListTest do
  @moduledoc false
  use ExUnit.Case
  import ArchethicCase

  alias Archethic.P2P.Message.ReplicationAttestationList
  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.TransactionChain.TransactionSummary

  test "serialization/deserialization" do
    msg = %ReplicationAttestationList{
      replications_attestations: [
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
        }
      ]
    }

    assert {^msg, <<>>} =
             msg
             |> ReplicationAttestationList.serialize()
             |> ReplicationAttestationList.deserialize()
  end
end
