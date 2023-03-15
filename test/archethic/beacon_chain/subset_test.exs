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
    Subset
  }

  alias Archethic.Crypto

  alias Archethic.Utils

  alias Archethic.P2P
  alias Archethic.P2P.Message.BeaconUpdate
  alias Archethic.P2P.Message.NewBeaconSlot
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Ping
  alias Archethic.P2P.Node

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
      authorization_date: DateTime.utc_now() |> DateTime.add(-1)
    })

    {:ok, subset: <<0>>}
  end

  test "add_end_of_node_sync/2 should insert end of node synchronization in the beacon slot", %{
    subset: subset
  } do
    start_supervised!({SummaryTimer, interval: "0 0 * * *"})
    start_supervised!({SlotTimer, interval: "0 0 * * *"})
    pid = start_supervised!({Subset, subset: subset})

    public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    :ok = Subset.add_end_of_node_sync(subset, %EndOfNodeSync{public_key: public_key})

    MockClient
    |> stub(:send_message, fn
      _, %NewBeaconSlot{}, _ ->
        {:ok, %Ok{}}
    end)

    assert %{
             current_slot: %Slot{
               end_of_node_synchronizations: [%EndOfNodeSync{public_key: ^public_key}]
             }
           } = :sys.get_state(pid)
  end

  describe "handle_info/1" do
    test "new transaction summary is added to the slot and include the storage node confirmation",
         %{subset: subset} do
      MockClient
      |> stub(:send_message, fn
        _, %TransactionSummary{}, _ ->
          {:ok, %Ok{}}

        _, %NewBeaconSlot{}, _ ->
          {:ok, %Ok{}}
      end)

      start_supervised!({SummaryTimer, interval: "0 0 * * *"})
      start_supervised!({SlotTimer, interval: "0 0 * * *"})
      pid = start_supervised!({Subset, subset: subset})

      tx_time = DateTime.utc_now()
      tx_address = <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>

      tx_summary = %TransactionSummary{
        address: tx_address,
        timestamp: tx_time,
        type: :node,
        fee: 0,
        validation_stamp_checksum: :crypto.strong_rand_bytes(32)
      }

      sig = Crypto.sign_with_last_node_key(TransactionSummary.serialize(tx_summary))

      send(
        pid,
        {:new_replication_attestation,
         %ReplicationAttestation{transaction_summary: tx_summary, confirmations: [{0, sig}]}}
      )

      assert %{
               current_slot: %Slot{
                 transaction_attestations: [
                   %ReplicationAttestation{
                     transaction_summary: %TransactionSummary{
                       address: ^tx_address
                     },
                     confirmations: [{0, ^sig}]
                   }
                 ]
               }
             } = :sys.get_state(pid)
    end

    test "new transaction summary's confirmation added to the slot",
         %{subset: subset} do
      start_supervised!({SummaryTimer, interval: "0 0 * * *"})
      start_supervised!({SlotTimer, interval: "0 0 * * *"})
      pid = start_supervised!({Subset, subset: subset})

      MockClient
      |> stub(:send_message, fn _, %NewBeaconSlot{}, _ ->
        {:ok, %Ok{}}
      end)

      tx_time = DateTime.utc_now()
      tx_address = <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>

      tx_summary = %TransactionSummary{
        address: tx_address,
        timestamp: tx_time,
        type: :node,
        fee: 0,
        validation_stamp_checksum: :crypto.strong_rand_bytes(32)
      }

      tx_summary_payload = TransactionSummary.serialize(tx_summary)

      sig1 = Crypto.sign_with_last_node_key(tx_summary_payload)

      {_, node2_private_key} = Crypto.generate_deterministic_keypair("node2")
      sig2 = Crypto.sign(tx_summary_payload, node2_private_key)

      send(
        pid,
        {:new_replication_attestation,
         %ReplicationAttestation{transaction_summary: tx_summary, confirmations: [{0, sig1}]}}
      )

      send(
        pid,
        {:new_replication_attestation,
         %ReplicationAttestation{transaction_summary: tx_summary, confirmations: [{1, sig2}]}}
      )

      assert %{
               current_slot: %Slot{
                 transaction_attestations: [
                   %ReplicationAttestation{
                     transaction_summary: %TransactionSummary{
                       address: ^tx_address
                     },
                     confirmations: confirmations
                   }
                 ]
               }
             } = :sys.get_state(pid)

      assert Enum.count(confirmations) == 2
    end

    test "new transaction summary's should be refused if it is too old",
         %{subset: subset} do
      MockClient
      |> stub(:send_message, fn
        _, %TransactionSummary{}, _ ->
          {:ok, %Ok{}}

        _, %NewBeaconSlot{}, _ ->
          {:ok, %Ok{}}
      end)

      start_supervised!({SummaryTimer, interval: "0 0 * * *"})
      start_supervised!({SlotTimer, interval: "0 */10 * * *"})
      pid = start_supervised!({Subset, subset: subset})

      # Tx from last summary should pass
      tx_time = DateTime.utc_now() |> DateTime.add(-1, :hour)
      tx_address = <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>

      tx_summary = %TransactionSummary{
        address: tx_address,
        timestamp: tx_time,
        type: :node,
        fee: 0,
        validation_stamp_checksum: :crypto.strong_rand_bytes(32)
      }

      sig = Crypto.sign_with_last_node_key(TransactionSummary.serialize(tx_summary))

      send(
        pid,
        {:new_replication_attestation,
         %ReplicationAttestation{transaction_summary: tx_summary, confirmations: [{0, sig}]}}
      )

      # Tx from 2 last summary should not pass
      tx_time = DateTime.utc_now() |> DateTime.add(-2, :hour)
      tx_address2 = <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>

      tx_summary = %TransactionSummary{
        address: tx_address2,
        timestamp: tx_time,
        type: :node,
        fee: 0,
        validation_stamp_checksum: :crypto.strong_rand_bytes(32)
      }

      sig2 = Crypto.sign_with_last_node_key(TransactionSummary.serialize(tx_summary))

      send(
        pid,
        {:new_replication_attestation,
         %ReplicationAttestation{transaction_summary: tx_summary, confirmations: [{0, sig2}]}}
      )

      assert %{
               current_slot: %Slot{
                 transaction_attestations: [
                   %ReplicationAttestation{
                     transaction_summary: %TransactionSummary{
                       address: ^tx_address
                     },
                     confirmations: [{0, ^sig}]
                   }
                 ]
               }
             } = :sys.get_state(pid)
    end

    test "new slot is created when receive a :create_slot message", %{subset: subset} do
      start_supervised!({SummaryTimer, interval: "0 0 * * *"})
      start_supervised!({SlotTimer, interval: "0 0 * * *"})
      pid = start_supervised!({Subset, subset: subset})

      tx_time = DateTime.utc_now()
      tx_address = <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        last_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        geo_patch: "AAA",
        network_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      })

      tx_summary = %TransactionSummary{
        address: tx_address,
        timestamp: tx_time,
        type: :keychain,
        movements_addresses: [
          <<0, 0, 109, 2, 63, 124, 238, 101, 213, 214, 64, 58, 218, 10, 35, 62, 202, 12, 64, 11,
            232, 210, 105, 102, 193, 193, 24, 54, 42, 200, 226, 13, 38, 69>>,
          <<0, 0, 8, 253, 201, 142, 182, 78, 169, 132, 29, 19, 74, 3, 142, 207, 219, 127, 147, 40,
            24, 44, 170, 214, 171, 224, 29, 177, 205, 226, 88, 62, 248, 84>>
        ],
        fee: 0,
        validation_stamp_checksum: :crypto.strong_rand_bytes(32)
      }

      tx_summary_payload = TransactionSummary.serialize(tx_summary)

      sig1 = Crypto.sign_with_last_node_key(tx_summary_payload)

      send(
        pid,
        {:new_replication_attestation,
         %ReplicationAttestation{transaction_summary: tx_summary, confirmations: [{0, sig1}]}}
      )

      me = self()

      MockClient
      |> stub(:send_message, fn
        _, %NewBeaconSlot{slot: slot}, _ ->
          send(me, {:beacon_slot, slot})
          {:ok, %Ok{}}

        _, %Ping{}, _ ->
          {:ok, %Ok{}}
      end)

      Process.sleep(200)

      send(pid, {:create_slot, DateTime.utc_now()})

      assert_receive {:beacon_slot, slot}

      assert %Slot{
               transaction_attestations: [
                 %ReplicationAttestation{
                   transaction_summary: %TransactionSummary{
                     address: ^tx_address
                   },
                   confirmations: [{_, _}]
                 }
               ]
             } = slot
    end

    test "new summary is created when the slot time is the summary time", %{
      subset: subset
    } do
      MockClient
      |> stub(:send_message, fn
        _, %Ping{}, _ ->
          {:ok, %Ok{}}

        _, %NewBeaconSlot{slot: slot = %Slot{subset: subset}}, _ ->
          SummaryCache.add_slot(subset, slot)
          {:ok, %Ok{}}
      end)

      MockClient
      |> stub(:get_availability_timer, fn _, _ -> 0 end)

      summary_interval = "*/3 * * * *"
      start_supervised!({SummaryTimer, interval: summary_interval})
      start_supervised!({SlotTimer, interval: "*/1 * * * *"})
      start_supervised!(SummaryCache)
      File.mkdir_p!(Utils.mut_dir())
      pid = start_supervised!({Subset, subset: subset})

      allow(MockClient, self(), NewBeaconSlot)

      tx_time = DateTime.utc_now() |> DateTime.truncate(:millisecond)
      tx_address = <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key:
          <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>,
        last_public_key:
          <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>,
        geo_patch: "AAA",
        network_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: ~U[2020-09-01 00:00:00Z],
        enrollment_date: ~U[2020-09-01 00:00:00Z]
      })

      tx_summary = %TransactionSummary{
        address: tx_address,
        timestamp: tx_time,
        type: :keychain,
        movements_addresses: [
          <<0, 0, 109, 2, 63, 124, 238, 101, 213, 214, 64, 58, 218, 10, 35, 62, 202, 12, 64, 11,
            232, 210, 105, 102, 193, 193, 24, 54, 42, 200, 226, 13, 38, 69>>,
          <<0, 0, 8, 253, 201, 142, 182, 78, 169, 132, 29, 19, 74, 3, 142, 207, 219, 127, 147, 40,
            24, 44, 170, 214, 171, 224, 29, 177, 205, 226, 88, 62, 248, 84>>
        ],
        fee: 0,
        validation_stamp_checksum: :crypto.strong_rand_bytes(32)
      }

      send(
        pid,
        {:new_replication_attestation, %ReplicationAttestation{transaction_summary: tx_summary}}
      )

      me = self()

      MockDB
      |> stub(:write_beacon_summary, fn
        %Summary{
          transaction_attestations: [
            %ReplicationAttestation{
              transaction_summary: ^tx_summary
            }
          ]
        } ->
          send(me, :beacon_transaction_summary_stored)
      end)

      offset = Archethic.Utils.time_offset(summary_interval)
      Process.sleep(offset * 1000)

      now =
        DateTime.utc_now()
        |> DateTime.truncate(:millisecond)

      send(pid, {:create_slot, now})
      assert_receive :beacon_transaction_summary_stored
    end
  end

  test "subscribed nodes are being getting subscribed & added to beacon pool directly via subset",
       %{
         subset: subset
       } do
    start_supervised!({SummaryTimer, interval: "0 0 * * *"})
    start_supervised!({SlotTimer, interval: "0 0 * * *"})
    pid = start_supervised!({Subset, subset: subset})

    public_key1 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    Subset.subscribe_for_beacon_updates(subset, public_key1)

    assert %{subscribed_nodes: [^public_key1]} = :sys.get_state(pid)
    assert [^public_key1] = Map.get(:sys.get_state(pid), :subscribed_nodes)

    public_key2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    Subset.subscribe_for_beacon_updates(subset, public_key2)

    assert %{subscribed_nodes: [^public_key2, ^public_key1]} = :sys.get_state(pid)
  end

  test "subscribed nodes are being getting subscribed & added to beacon pool via Beacon chain", %{
    subset: subset
  } do
    start_supervised!({SummaryTimer, interval: "0 0 * * *"})
    start_supervised!({SlotTimer, interval: "0 0 * * *"})
    pid = start_supervised!({Subset, subset: subset})

    first_public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: first_public_key,
      last_public_key:
        <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>,
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: ~U[2020-09-01 00:00:00Z]
    })

    me = self()

    tx_summary = %TransactionSummary{
      address: <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>,
      timestamp: DateTime.utc_now(),
      type: :keychain,
      movements_addresses: [
        <<0, 0, 109, 2, 63, 124, 238, 101, 213, 214, 64, 58, 218, 10, 35, 62, 202, 12, 64, 11,
          232, 210, 105, 102, 193, 193, 24, 54, 42, 200, 226, 13, 38, 69>>,
        <<0, 0, 8, 253, 201, 142, 182, 78, 169, 132, 29, 19, 74, 3, 142, 207, 219, 127, 147, 40,
          24, 44, 170, 214, 171, 224, 29, 177, 205, 226, 88, 62, 248, 84>>
      ],
      fee: 0,
      validation_stamp_checksum: :crypto.strong_rand_bytes(32)
    }

    tx_summary_payload = TransactionSummary.serialize(tx_summary)

    sig1 = Crypto.sign_with_last_node_key(tx_summary_payload)

    send(
      pid,
      {:new_replication_attestation,
       %ReplicationAttestation{transaction_summary: tx_summary, confirmations: [{0, sig1}]}}
    )

    MockClient
    |> stub(:send_message, fn
      _, %BeaconUpdate{transaction_attestations: transaction_attestations}, _ ->
        send(me, {:transaction_attestations, transaction_attestations})
        {:ok, %Ok{}}

      _, %ReplicationAttestation{}, _ ->
        {:ok, %Ok{}}

      _, %NewBeaconSlot{}, _ ->
        {:ok, %Ok{}}

      _, %Ping{}, _ ->
        {:ok, %Ok{}}
    end)

    Subset.subscribe_for_beacon_updates(subset, first_public_key)

    assert [^first_public_key] = Map.get(:sys.get_state(pid), :subscribed_nodes)
    assert_receive {:transaction_attestations, [%ReplicationAttestation{}]}
  end
end
