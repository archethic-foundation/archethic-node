defmodule Archethic.BeaconChain.SubsetTest do
  use ArchethicCase, async: false

  alias Archethic.BeaconChain.{
    ReplicationAttestation,
    Slot,
    Slot.EndOfNodeSync,
    SlotTimer,
    Summary,
    SummaryTimer,
    Subset.SummaryCache,
    Subset.StatsCollector,
    Subset
  }

  alias Archethic.Crypto

  alias Archethic.Utils

  alias Archethic.P2P
  alias Archethic.P2P.Message.BeaconUpdate
  alias Archethic.P2P.Message.NewBeaconSlot
  alias Archethic.P2P.Message.GetNetworkStats
  alias Archethic.P2P.Message.NetworkStats
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Ping
  alias Archethic.P2P.Node

  alias Archethic.SelfRepair.Scheduler, as: SelfRepairScheduler

  alias Archethic.TransactionChain.TransactionSummary

  import Mox

  setup do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.first_node_public_key(),
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: ~U[2023-07-11 00:00:00Z]
    })

    StatsCollector.start_link()

    {:ok, subset: <<0>>}
  end

  test "add_end_of_node_sync/2 should insert end of node synchronization in the beacon slot", %{
    subset: subset
  } do
    Application.put_env(:archethic, SummaryTimer, interval: "0 0 * * *")
    Application.put_env(:archethic, SlotTimer, interval: "0 0 * * *")

    pid = start_supervised!({Subset, subset: subset})

    end_of_sync = %EndOfNodeSync{
      public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    }

    :ok = Subset.add_end_of_node_sync(subset, end_of_sync)

    assert %{current_slot: %Slot{end_of_node_synchronizations: [^end_of_sync]}} =
             :sys.get_state(pid)
  end

  describe "handle_info/1" do
    test "new transaction summary is added to the slot and include the storage node confirmation",
         %{subset: subset} do
      Application.put_env(:archethic, SummaryTimer, interval: "0 0 * * *")
      Application.put_env(:archethic, SlotTimer, interval: "0 */10 * * *")

      pid = start_supervised!({Subset, subset: subset})

      slot_time = ~U[2023-07-11 00:20:00Z]

      # Replace state to update date for test purpose
      :sys.replace_state(pid, fn state ->
        Map.update!(state, :current_slot, fn slot -> %Slot{slot | slot_time: slot_time} end)
      end)

      attestation = create_attestation(subset, ~U[2023-07-11 00:15:00Z])

      send(pid, {:new_replication_attestation, attestation})

      assert %{current_slot: %Slot{transaction_attestations: [^attestation]}} =
               :sys.get_state(pid)
    end

    test "new transaction summary's confirmation added to the slot",
         %{subset: subset} do
      Application.put_env(:archethic, SummaryTimer, interval: "0 0 * * *")
      Application.put_env(:archethic, SlotTimer, interval: "0 */10 * * *")

      pid = start_supervised!({Subset, subset: subset})

      slot_time = ~U[2023-07-11 00:20:00Z]

      # Replace state to update date for test purpose
      :sys.replace_state(pid, fn state ->
        Map.update!(state, :current_slot, fn slot -> %Slot{slot | slot_time: slot_time} end)
      end)

      attestation1 =
        %ReplicationAttestation{transaction_summary: tx_summary} =
        create_attestation(subset, ~U[2023-07-11 00:15:00Z])

      tx_summary_payload = TransactionSummary.serialize(tx_summary)

      {_, node2_private_key} = Crypto.generate_deterministic_keypair("node2")
      sig2 = Crypto.sign(tx_summary_payload, node2_private_key)

      attestation2 = %ReplicationAttestation{attestation1 | confirmations: [{1, sig2}]}

      expected_attestation = %ReplicationAttestation{
        transaction_summary: tx_summary,
        confirmations: attestation1.confirmations ++ attestation2.confirmations
      }

      send(pid, {:new_replication_attestation, attestation1})
      send(pid, {:new_replication_attestation, attestation2})

      assert %{current_slot: %Slot{transaction_attestations: [^expected_attestation]}} =
               :sys.get_state(pid)
    end

    test "new transaction summary's should be refused if it is too old",
         %{subset: subset} do
      Application.put_env(:archethic, SummaryTimer, interval: "0 0 * * *")
      Application.put_env(:archethic, SlotTimer, interval: "0 */10 * * *")

      pid = start_supervised!({Subset, subset: subset})

      slot_time = ~U[2023-07-11 02:20:00Z]

      # Replace state to update date for test purpose
      :sys.replace_state(pid, fn state ->
        Map.update!(state, :current_slot, fn slot -> %Slot{slot | slot_time: slot_time} end)
      end)

      # Tx from last summary should pass
      attestation1 = create_attestation(subset, ~U[2023-07-11 01:15:00Z])

      send(pid, {:new_replication_attestation, attestation1})

      assert %{current_slot: %Slot{transaction_attestations: [^attestation1]}} =
               :sys.get_state(pid)

      # Tx from 2 last summary should not pass
      attestation2 = create_attestation(subset, ~U[2023-07-11 00:15:00Z])

      send(pid, {:new_replication_attestation, attestation2})

      assert %{current_slot: %Slot{transaction_attestations: [^attestation1]}} =
               :sys.get_state(pid)
    end

    test "new slot is created when receive :current_epoch_of_slot_timer message", %{
      subset: subset
    } do
      Application.put_env(:archethic, SummaryTimer, interval: "0 0 * * *")
      Application.put_env(:archethic, SlotTimer, interval: "0 */10 * * *")

      pid = start_supervised!({Subset, subset: subset})

      slot_time = ~U[2023-07-11 00:20:00Z]

      # Replace state to update date for test purpose
      :sys.replace_state(pid, fn state ->
        Map.update!(state, :current_slot, fn slot -> %Slot{slot | slot_time: slot_time} end)
      end)

      attestation = create_attestation(subset, ~U[2023-07-11 00:15:00Z])

      send(pid, {:new_replication_attestation, attestation})

      me = self()

      MockClient
      |> expect(:send_message, fn _, %NewBeaconSlot{slot: slot}, _ ->
        send(me, {:beacon_slot, slot})
        {:ok, %Ok{}}
      end)

      send(pid, {:current_epoch_of_slot_timer, slot_time})

      assert_receive {:beacon_slot, slot}

      assert %Slot{transaction_attestations: [^attestation]} = slot
    end

    test "new summary is created when the slot time is the summary time", %{
      subset: subset
    } do
      # This is needed to get network coordinates's task timeout
      start_supervised!({SelfRepairScheduler, interval: "*/10 * * * *"})

      Application.put_env(:archethic, SummaryTimer, interval: "0 0 * * *")
      Application.put_env(:archethic, SlotTimer, interval: "0 */10 * * *")

      start_supervised!(SummaryCache)
      pid = start_supervised!({Subset, subset: subset})

      mut_dir = Utils.mut_dir()
      File.mkdir_p!(mut_dir)

      # Nodes for network patch calculation
      node1_key = <<0::24, :crypto.strong_rand_bytes(31)::binary>>
      node2_key = <<0::24, :crypto.strong_rand_bytes(31)::binary>>

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: node1_key,
        last_public_key: node1_key,
        geo_patch: "AAA",
        network_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: ~U[2023-07-11 00:00:00Z],
        enrollment_date: ~U[2023-07-11 00:00:00Z]
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3001,
        first_public_key: node2_key,
        last_public_key: node2_key,
        geo_patch: "AAA",
        network_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: ~U[2023-07-11 00:00:00Z],
        enrollment_date: ~U[2023-07-11 00:00:00Z]
      })

      MockClient
      |> stub(:send_message, fn
        _, %Ping{}, _ ->
          {:ok, %Ok{}}

        _, %GetNetworkStats{}, _ ->
          {:ok,
           %NetworkStats{
             stats: %{
               subset => %{
                 node1_key => [%{latency: 90}, %{latency: 100}],
                 node2_key => [%{latency: 90}, %{latency: 100}]
               }
             }
           }}
      end)
      |> expect(:get_availability_timer, 4, fn _, _ -> 0 end)

      # slot time matches summary time interval
      slot_time = ~U[2023-07-11 01:00:00Z]

      # Replace state to update date for test purpose
      :sys.replace_state(pid, fn state ->
        Map.update!(state, :current_slot, fn slot -> %Slot{slot | slot_time: slot_time} end)
      end)

      attestation = create_attestation(subset, ~U[2023-07-11 00:55:00Z])

      send(pid, {:new_replication_attestation, attestation})

      # Add old slot in SummaryCache to ensure it will be deleted
      %{current_slot: slot} = :sys.get_state(pid)
      old_slot = %Slot{slot | slot_time: ~U[2023-07-11 00:50:00Z]}
      SummaryCache.add_slot(subset, old_slot, Crypto.first_node_public_key())

      me = self()

      MockDB
      |> expect(:write_beacon_summary, fn summary -> send(me, {:summary_stored, summary}) end)

      # subset process is dependant of stats collector
      send(Process.whereis(StatsCollector), {:next_summary_time, ~U[2023-07-11 02:00:00Z]})

      send(pid, {:current_epoch_of_slot_timer, slot_time})

      assert_receive {:summary_stored, summary}, 2000

      assert %Summary{
               subset: ^subset,
               summary_time: ^slot_time,
               transaction_attestations: [^attestation],
               network_patches: ["F7A", "78A"]
             } = summary
    end
  end

  test "subscribed nodes are being getting subscribed & added to beacon pool directly via subset",
       %{
         subset: subset
       } do
    Application.put_env(:archethic, SummaryTimer, interval: "0 0 * * *")
    Application.put_env(:archethic, SlotTimer, interval: "0 */10 * * *")

    pid = start_supervised!({Subset, subset: subset})

    public_key1 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    Subset.subscribe_for_beacon_updates(subset, public_key1)

    assert %{subscribed_nodes: [^public_key1]} = :sys.get_state(pid)

    public_key2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    Subset.subscribe_for_beacon_updates(subset, public_key2)

    assert %{subscribed_nodes: [^public_key2, ^public_key1]} = :sys.get_state(pid)
  end

  test "subscribed nodes are being getting subscribed & added to beacon pool via Beacon chain", %{
    subset: subset
  } do
    Application.put_env(:archethic, SummaryTimer, interval: "0 0 * * *")
    Application.put_env(:archethic, SlotTimer, interval: "0 0 * * *")

    pid = start_supervised!({Subset, subset: subset})

    subscribed_node = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      last_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: ~U[2020-09-01 00:00:00Z]
    }

    P2P.add_and_connect_node(subscribed_node)
    # slot time matches summary time interval
    slot_time = ~U[2023-07-11 01:00:00Z]

    # Replace state to update date for test purpose
    :sys.replace_state(pid, fn state ->
      Map.update!(state, :current_slot, fn slot -> %Slot{slot | slot_time: slot_time} end)
    end)

    attestation = create_attestation(subset, ~U[2023-07-11 00:55:00Z])

    send(pid, {:new_replication_attestation, attestation})

    me = self()

    MockClient
    |> expect(
      :send_message,
      fn ^subscribed_node, %BeaconUpdate{transaction_attestations: attestations}, _ ->
        send(me, {:transaction_attestations, attestations})
        {:ok, %Ok{}}
      end
    )

    Subset.subscribe_for_beacon_updates(subset, subscribed_node.first_public_key)

    assert_receive {:transaction_attestations, [^attestation]}
  end

  defp create_attestation(subset, time) do
    tx_summary = %TransactionSummary{
      address: <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>,
      timestamp: time,
      type: :keychain,
      movements_addresses: [],
      fee: 0,
      validation_stamp_checksum: :crypto.strong_rand_bytes(32),
      genesis_address: ArchethicCase.random_address()
    }

    sig = tx_summary |> TransactionSummary.serialize() |> Crypto.sign_with_last_node_key()

    %ReplicationAttestation{transaction_summary: tx_summary, confirmations: [{0, sig}]}
  end
end
