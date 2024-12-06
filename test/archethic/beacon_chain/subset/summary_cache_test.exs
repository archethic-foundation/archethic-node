defmodule Archethic.BeaconChain.Subset.SummaryCacheTest do
  use ArchethicCase

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Subset.SummaryCache

  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Slot.EndOfNodeSync
  alias Archethic.BeaconChain.SummaryTimer

  alias Archethic.Crypto

  alias Archethic.Utils

  alias Archethic.TransactionChain.TransactionSummary

  test "should clean the previous backup on summary time" do
    Application.put_env(:archethic, SummaryTimer, interval: "0 * * * * *")

    {:ok, pid} = SummaryCache.start_link()
    File.mkdir_p!(Utils.mut_dir())

    subset = <<0>>

    slot_pre_summary = %Slot{
      slot_time: ~U[2023-01-01 07:59:50Z],
      subset: subset
    }

    slot_pre_summary2 = %Slot{
      slot_time: ~U[2023-01-01 08:00:00Z],
      subset: subset
    }

    slot_post_summary = %Slot{
      slot_time: ~U[2023-01-01 08:00:20Z],
      subset: subset
    }

    summary_time = ~U[2023-01-01 08:01:00Z]

    SummaryCache.add_slot(slot_pre_summary, "node_key")
    SummaryCache.add_slot(slot_pre_summary2, "node_key")
    SummaryCache.add_slot(slot_post_summary, "node_key")

    send(pid, {:current_epoch_of_slot_timer, summary_time})
    Process.sleep(100)

    previous_summary_time = SummaryTimer.previous_summary(summary_time)
    recover_path = Utils.mut_dir("slot_backup-#{DateTime.to_unix(previous_summary_time)}")
    refute File.exists?(recover_path)
  end

  test "stream_slots/2 should stream the slot from file" do
    Application.put_env(:archethic, SummaryTimer, interval: "0 0 * * * *")
    File.mkdir_p!(Utils.mut_dir())

    next_summary_time = SummaryTimer.next_summary(DateTime.utc_now())
    # path = Utils.mut_dir("slot_backup-#{DateTime.to_unix(next_summary_time)}")

    {:ok, _pid} = SummaryCache.start_link()

    slot = %Slot{
      subset: <<0>>,
      slot_time: DateTime.add(next_summary_time, -20, :minute),
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
          confirmations: [
            {0, :crypto.strong_rand_bytes(32)}
          ]
        }
      ],
      end_of_node_synchronizations: [
        %EndOfNodeSync{
          public_key: ArchethicCase.random_public_key(),
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

    slot2 = %Slot{
      subset: <<0>>,
      slot_time: DateTime.add(next_summary_time, -10, :minute),
      transaction_attestations: [],
      end_of_node_synchronizations: [],
      p2p_view: %{
        availabilities: <<600::16, 0::16>>,
        network_stats: [
          %{latency: 10},
          %{latency: 0}
        ]
      }
    }

    node_key = Crypto.first_node_public_key()
    :ok = SummaryCache.add_slot(slot, node_key)
    :ok = SummaryCache.add_slot(slot2, node_key)

    slots =
      next_summary_time
      |> SummaryCache.stream_slots(<<0>>)
      |> Enum.sort_by(fn {slot, _} -> slot.slot_time end, {:asc, DateTime})

    assert [{^slot, ^node_key}, {^slot2, ^node_key}] = slots
  end

  test "should cleanup as soon as selfrepair is triggered" do
    Application.put_env(:archethic, SummaryTimer, interval: "0 * * * * *")
    {:ok, pid} = SummaryCache.start_link()
    File.mkdir_p!(Utils.mut_dir())

    now = DateTime.utc_now()

    node_key = Crypto.first_node_public_key()
    subset = <<0>>

    slot_pre_summary = %Slot{
      slot_time: SummaryTimer.previous_summary(now),
      subset: subset
    }

    slot_post_summary = %Slot{
      slot_time: SummaryTimer.next_summary(now),
      subset: subset
    }

    SummaryCache.add_slot(slot_pre_summary, node_key)
    SummaryCache.add_slot(slot_post_summary, node_key)

    send(pid, :self_repair_sync)
    Process.sleep(50)

    assert [{^slot_post_summary, ^node_key}] =
             slot_post_summary.slot_time
             |> SummaryCache.stream_slots(<<0>>)
             |> Enum.to_list()
  end
end
