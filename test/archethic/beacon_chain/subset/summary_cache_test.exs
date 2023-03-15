defmodule Archethic.BeaconChain.Subset.SummaryCacheTest do
  use ArchethicCase

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Subset.SummaryCache

  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Slot.EndOfNodeSync

  alias Archethic.BeaconChain.SummaryTimer

  alias Archethic.Utils

  alias Archethic.TransactionChain.TransactionSummary

  test "summary cache should backup a slot, recover it on restart and delete backup on pop_slots" do
    {:ok, _pid} = SummaryTimer.start_link([interval: "0 0 * * * * *"], [])
    File.mkdir_p!(Utils.mut_dir())

    path = Utils.mut_dir("slot_backup")

    {:ok, pid} = SummaryCache.start_link()

    slot = %Slot{
      subset: <<0>>,
      slot_time: DateTime.utc_now() |> DateTime.truncate(:second),
      transaction_attestations: [
        %ReplicationAttestation{
          transaction_summary: %TransactionSummary{
            address:
              <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232,
                166, 99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
            timestamp: ~U[2020-06-25 15:11:53.000Z],
            type: :transfer,
            movements_addresses: [],
            fee: 10_000_000,
            validation_stamp_checksum: :crypto.strong_rand_bytes(32)
          },
          confirmations: [
            {0,
             <<129, 204, 107, 81, 235, 88, 234, 207, 125, 1, 208, 227, 239, 175, 78, 217, 100,
               172, 67, 228, 131, 42, 177, 200, 54, 225, 34, 241, 35, 226, 108, 138, 201, 2, 32,
               75, 92, 49, 194, 42, 113, 154, 20, 43, 216, 176, 11, 159, 188, 119, 6, 8, 48, 201,
               244, 138, 99, 52, 22, 1, 97, 123, 140, 195>>}
          ]
        }
      ],
      end_of_node_synchronizations: [
        %EndOfNodeSync{
          public_key:
            <<0, 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
              100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
          timestamp: ~U[2020-06-25 15:11:53Z]
        }
      ],
      p2p_view: %{
        availabilities: <<600::16, 0::16>>,
        network_stats: [
          %{latency: 10},
          %{latency: 0}
        ]
      }
    }

    :ok = SummaryCache.add_slot(<<0>>, slot)

    assert [^slot] = :ets.lookup_element(:archethic_summary_cache, <<0>>, 2)
    assert File.exists?(path)

    GenServer.stop(pid)
    assert Process.alive?(pid) == false

    {:ok, _} = SummaryCache.start_link()

    slots = SummaryCache.pop_slots(<<0>>)
    assert !File.exists?(path)

    assert [^slot] = slots
  end
end
