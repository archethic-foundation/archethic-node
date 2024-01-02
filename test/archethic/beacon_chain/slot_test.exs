defmodule Archethic.BeaconChain.SlotTest do
  use ExUnit.Case

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Slot.EndOfNodeSync
  alias Archethic.TransactionChain.TransactionSummary

  doctest Slot

  test "symmetric serialization" do
    slot = %Slot{
      subset: <<0>>,
      slot_time: ~U[2021-01-20 10:10:00Z],
      transaction_attestations: [
        %ReplicationAttestation{
          transaction_summary: %TransactionSummary{
            address: ArchethicCase.random_address(),
            timestamp: ~U[2020-06-25 15:11:53Z],
            type: :transfer,
            movements_addresses: [],
            fee: 10_000_000,
            validation_stamp_checksum: :crypto.strong_rand_bytes(32)
          },
          confirmations: [{0, :crypto.strong_rand_bytes(32)}]
        }
      ],
      end_of_node_synchronizations: [
        %EndOfNodeSync{
          public_key: ArchethicCase.random_public_key(),
          timestamp: ~U[2020-06-25 15:11:53Z]
        }
      ],
      p2p_view: %{
        availabilities: <<600::16, 356::16>>,
        network_stats: [
          %{latency: 10},
          %{latency: 0}
        ]
      }
    }

    assert {^slot, _} =
             slot
             |> Slot.serialize()
             |> Slot.deserialize()
  end
end
