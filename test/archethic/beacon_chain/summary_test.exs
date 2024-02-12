defmodule Archethic.BeaconChain.SummaryTest do
  use ExUnit.Case

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Summary
  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.P2P.Node

  doctest Summary

  test "symmetric serialization" do
    summary = %Summary{
      subset: <<0>>,
      summary_time: ~U[2021-01-20 00:00:00Z],
      availability_adding_time: 900,
      transaction_attestations: [
        %ReplicationAttestation{
          transaction_summary: %TransactionSummary{
            address: ArchethicCase.random_address(),
            timestamp: ~U[2020-06-25 15:11:53.000Z],
            type: :transfer,
            movements_addresses: [],
            fee: 10_000_000,
            validation_stamp_checksum: :crypto.strong_rand_bytes(32),
            genesis_address: ArchethicCase.random_address()
          },
          confirmations: [{0, :crypto.strong_rand_bytes(32)}]
        }
      ],
      node_availabilities: <<1::1, 1::1>>,
      node_average_availabilities: [1.0, 1.0],
      end_of_node_synchronizations: [ArchethicCase.random_public_key()],
      network_patches: ["A0C", "0EF"]
    }

    assert {^summary, _} =
             summary
             |> Summary.serialize()
             |> Summary.deserialize()
  end
end
