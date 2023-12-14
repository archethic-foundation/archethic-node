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

  import Mock

  test "should clean the previous backup on summary time" do
    {:ok, _pid} = SummaryTimer.start_link([interval: "0 * * * * *"], [])
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

    SummaryCache.add_slot(subset, slot_pre_summary, "node_key")
    SummaryCache.add_slot(subset, slot_pre_summary2, "node_key")
    SummaryCache.add_slot(subset, slot_post_summary, "node_key")

    send(pid, {:current_epoch_of_slot_timer, summary_time})
    Process.sleep(100)

    previous_summary_time = SummaryTimer.previous_summary(summary_time)
    recover_path = Utils.mut_dir("slot_backup-#{DateTime.to_unix(previous_summary_time)}")
    refute File.exists?(recover_path)
  end

  test_with_mock "should clean the previous backup and ets table on node up",
                 DateTime,
                 [:passthrough],
                 utc_now: fn -> ~U[2023-01-01 08:00:50Z] end do
    {:ok, _pid} = SummaryTimer.start_link([interval: "0 * * * * *"], [])
    {:ok, pid} = SummaryCache.start_link()
    File.mkdir_p!(Utils.mut_dir())

    subset = <<0>>

    slot_in_old_backup = %Slot{
      slot_time: ~U[2023-01-01 07:58:50Z],
      subset: subset
    }

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

    summary_time = ~U[2023-01-01 08:00:00Z]

    SummaryCache.add_slot(subset, slot_in_old_backup, "node_key")
    SummaryCache.add_slot(subset, slot_pre_summary, "node_key")
    SummaryCache.add_slot(subset, slot_pre_summary2, "node_key")
    SummaryCache.add_slot(subset, slot_post_summary, "node_key")

    send(pid, :node_up)
    Process.sleep(100)

    assert [{^slot_post_summary, "node_key"}] =
             subset
             |> SummaryCache.stream_current_slots()
             |> Enum.to_list()

    previous_summary_time = SummaryTimer.previous_summary(summary_time)
    recover_path = Utils.mut_dir("slot_backup-#{DateTime.to_unix(previous_summary_time)}")
    refute File.exists?(recover_path)
  end

  test "summary cache should backup a slot, recover it on restart" do
    {:ok, _pid} = SummaryTimer.start_link([interval: "0 0 * * * * *"], [])
    File.mkdir_p!(Utils.mut_dir())

    next_summary_time = SummaryTimer.next_summary(DateTime.utc_now())
    path = Utils.mut_dir("slot_backup-#{DateTime.to_unix(next_summary_time)}")

    {:ok, pid} = SummaryCache.start_link()

    slot = %Slot{
      subset: <<0>>,
      slot_time: DateTime.add(next_summary_time, -10, :minute),
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

    slot2 = %Slot{
      subset: <<0>>,
      slot_time: next_summary_time,
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
    :ok = SummaryCache.add_slot(<<0>>, slot, node_key)
    :ok = SummaryCache.add_slot(<<0>>, slot2, node_key)

    assert [{^slot, ^node_key}, {^slot2, ^node_key}] =
             :ets.lookup_element(:archethic_summary_cache, <<0>>, 2)

    assert File.exists?(path)

    GenServer.stop(pid)
    assert Process.alive?(pid) == false

    {:ok, _} = SummaryCache.start_link()

    slots = SummaryCache.stream_current_slots(<<0>>) |> Enum.to_list()
    assert [{^slot, ^node_key}, {^slot2, ^node_key}] = slots
  end

  test "should cleanup as soon as selfrepair is triggered" do
    {:ok, _pid} = SummaryTimer.start_link([interval: "0 * * * * *"], [])
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

    SummaryCache.add_slot(subset, slot_pre_summary, node_key)
    SummaryCache.add_slot(subset, slot_post_summary, node_key)

    send(pid, :self_repair_sync)
    Process.sleep(50)

    assert [{^slot_post_summary, ^node_key}] =
             subset
             |> SummaryCache.stream_current_slots()
             |> Enum.to_list()
  end
end
