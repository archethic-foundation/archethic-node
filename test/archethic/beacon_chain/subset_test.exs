defmodule Archethic.BeaconChain.SubsetTest do
  use ArchethicCase, async: false

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Slot.EndOfNodeSync
  alias Archethic.BeaconChain.SlotTimer
  alias Archethic.BeaconChain.Summary
  alias Archethic.BeaconChain.SummaryTimer

  alias Archethic.BeaconChain.Subset

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.BeaconUpdate
  alias Archethic.P2P.Message.NewBeaconTransaction
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Ping
  alias Archethic.P2P.Node
  # alias Archethic.P2P.Message.GetFirstAddress
  # alias Archethic.P2P.Message.NotFound

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionSummary

  import Mox

  setup do
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

    assert %{
             current_slot: %Slot{
               end_of_node_synchronizations: [%EndOfNodeSync{public_key: ^public_key}]
             }
           } = :sys.get_state(pid)
  end

  describe "handle_info/1" do
    test "new transaction summary is added to the slot and include the storage node confirmation",
         %{subset: subset} do
      start_supervised!({SummaryTimer, interval: "0 0 * * *"})
      start_supervised!({SlotTimer, interval: "0 0 * * *"})
      pid = start_supervised!({Subset, subset: subset})

      tx_time = DateTime.utc_now()
      tx_address = <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>

      tx_summary = %TransactionSummary{
        address: tx_address,
        timestamp: tx_time,
        type: :node,
        fee: 0
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

      tx_time = DateTime.utc_now()
      tx_address = <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>

      tx_summary = %TransactionSummary{
        address: tx_address,
        timestamp: tx_time,
        type: :node,
        fee: 0
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

    test "new slot is created when receive a :create_slot message", %{subset: subset} do
      start_supervised!({SummaryTimer, interval: "0 0 * * *"})
      start_supervised!({SlotTimer, interval: "0 0 * * *"})
      pid = start_supervised!({Subset, subset: subset})

      tx_time = DateTime.utc_now()
      tx_address = <<0::8, 0::8, subset::binary-size(1), :crypto.strong_rand_bytes(31)::binary>>

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
        fee: 0
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
        _, %NewBeaconTransaction{transaction: tx}, _ ->
          send(me, {:beacon_tx, tx})
          {:ok, %Ok{}}

        _, %Ping{}, _ ->
          Process.sleep(10)
          {:ok, %Ok{}}
      end)

      Process.sleep(200)

      send(pid, {:create_slot, DateTime.utc_now()})

      assert_receive {:beacon_tx,
                      %Transaction{type: :beacon, data: %TransactionData{content: content}}}

      assert {%Slot{
                transaction_attestations: [
                  %ReplicationAttestation{
                    transaction_summary: %TransactionSummary{
                      address: ^tx_address
                    },
                    confirmations: [{_, _}]
                  }
                ]
              }, _} = Slot.deserialize(content)
    end

    test "new summary is created when the slot time is the summary time", %{
      subset: subset
    } do
      summary_interval = "*/5 * * * *"
      start_supervised!({SummaryTimer, interval: summary_interval})
      start_supervised!({SlotTimer, interval: "0 0 * * *"})
      pid = start_supervised!({Subset, subset: subset})

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

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
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
        fee: 0
      }

      MockClient
      |> stub(:send_message, fn
        _, %Ping{}, _ ->
          Process.sleep(10)
          {:ok, %Ok{}}

        _, %NewBeaconTransaction{}, _ ->
          {:ok, %Ok{}}
      end)

      send(
        pid,
        {:new_replication_attestation, %ReplicationAttestation{transaction_summary: tx_summary}}
      )

      me = self()

      MockDB
      |> stub(:write_transaction_at, fn
        %Transaction{
          type: :beacon,
          data: %TransactionData{content: content}
        },
        _ ->
          assert {%Slot{
                    subset: ^subset,
                    p2p_view: %{
                      availabilities: <<1::1>>,
                      network_stats: [%{latency: _}]
                    },
                    transaction_attestations: [
                      %ReplicationAttestation{
                        transaction_summary: ^tx_summary
                      }
                    ]
                  }, _} = Slot.deserialize(content)

          send(me, :beacon_transaction_stored)

        %Transaction{type: :beacon_summary, data: %TransactionData{content: content}}, _ ->
          {%Summary{
             transaction_attestations: [
               %ReplicationAttestation{
                 transaction_summary: ^tx_summary
               }
             ]
           }, _} = Summary.deserialize(content)

          send(me, :beacon_transaction_summary_stored)
      end)

      offset = Archethic.Utils.time_offset(summary_interval)
      Process.sleep(offset * 1000)

      now =
        DateTime.utc_now()
        |> DateTime.truncate(:millisecond)

      send(pid, {:create_slot, now})
      assert_receive :beacon_transaction_stored
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
      fee: 0
    }

    tx_summary_payload = TransactionSummary.serialize(tx_summary)

    sig1 = Crypto.sign_with_last_node_key(tx_summary_payload)

    send(
      pid,
      {:new_replication_attestation,
       %ReplicationAttestation{transaction_summary: tx_summary, confirmations: [{0, sig1}]}}
    )

    MockClient
    |> expect(:send_message, fn
      _, %BeaconUpdate{transaction_attestations: transaction_attestations}, _ ->
        send(me, {:transaction_attestations, transaction_attestations})
        {:ok, %Ok{}}

      _, %ReplicationAttestation{}, _ ->
        {:ok, %Ok{}}

      _, %NewBeaconTransaction{}, _ ->
        {:ok, %Ok{}}
    end)

    Subset.subscribe_for_beacon_updates(subset, first_public_key)

    assert [^first_public_key] = Map.get(:sys.get_state(pid), :subscribed_nodes)
    assert_receive {:transaction_attestations, [%ReplicationAttestation{}]}
  end
end
