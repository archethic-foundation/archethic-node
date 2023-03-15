defmodule Archethic.SelfRepair.SyncTest do
  use ArchethicCase, async: false

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Archethic.BeaconChain.Summary, as: BeaconSummary
  alias Archethic.BeaconChain.SummaryAggregate
  alias Archethic.BeaconChain.SummaryTimer, as: BeaconSummaryTimer

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Message.BeaconSummaryList
  alias Archethic.P2P.Message.GetBeaconSummaries
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetTransactionChain
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetGenesisAddress

  alias Archethic.PubSub

  alias Archethic.TransactionFactory

  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.SharedSecrets.MemTables.NetworkLookup

  alias Archethic.SelfRepair.Sync

  alias Archethic.Utils

  import Mox

  describe "last_sync_date/0" do
    test "should get nil if not last sync file and not prior nodes" do
      assert Sync.last_sync_date() == nil
    end

    test "should get the last sync date from the db" do
      last_sync_date = DateTime.utc_now() |> DateTime.add(-60) |> Utils.truncate_datetime()

      MockDB
      |> stub(:get_bootstrap_info, fn "last_sync_time" ->
        last_sync_date
        |> DateTime.to_unix()
        |> Integer.to_string()
      end)

      assert Sync.last_sync_date() == last_sync_date
    end
  end

  test "store_last_sync_date/1 should store the last sync date into the last sync file" do
    last_sync_date = DateTime.utc_now() |> DateTime.add(-60) |> Utils.truncate_datetime()
    last_sync_time = DateTime.to_unix(last_sync_date) |> Integer.to_string()

    me = self()

    MockDB
    |> stub(:set_bootstrap_info, fn "last_sync_time", time ->
      send(me, {:last_sync_time, time})
      :ok
    end)

    :ok = Sync.store_last_sync_date(last_sync_date)

    assert_received {:last_sync_time, ^last_sync_time}
  end

  describe "load_missed_transactions/2" do
    setup do
      start_supervised!({BeaconSummaryTimer, interval: "0 0 0 * * * *"})
      start_supervised!({BeaconSlotTimer, interval: "* * * * * *"})

      welcome_node_keypair = Crypto.derive_keypair("welcome_node", 0)

      welcome_node = %Node{
        first_public_key: elem(welcome_node_keypair, 0),
        last_public_key: elem(welcome_node_keypair, 0),
        available?: true,
        geo_patch: "BBB",
        network_patch: "BBB",
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        enrollment_date: DateTime.utc_now(),
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-(86_400 * 10))
      }

      coordinator_node = %Node{
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        authorized?: true,
        available?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-(86_400 * 10)),
        geo_patch: "AAA",
        network_patch: "AAA",
        reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        enrollment_date: DateTime.utc_now()
      }

      storage_node_keypair1 = Crypto.derive_keypair("node_keypair", 1)
      storage_node_keypair2 = Crypto.derive_keypair("node_keypair", 2)

      storage_nodes = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: elem(storage_node_keypair1, 0),
          last_public_key: elem(storage_node_keypair1, 0),
          available?: true,
          geo_patch: "BBB",
          network_patch: "BBB",
          reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          enrollment_date: DateTime.utc_now()
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: elem(storage_node_keypair2, 0),
          last_public_key: elem(storage_node_keypair2, 0),
          available?: true,
          geo_patch: "BBB",
          network_patch: "BBB",
          reward_address: :crypto.strong_rand_bytes(32),
          enrollment_date: DateTime.utc_now()
        }
      ]

      Enum.each(storage_nodes, &P2P.add_and_connect_node(&1))

      P2P.add_and_connect_node(welcome_node)
      P2P.add_and_connect_node(coordinator_node)

      {:ok,
       %{
         welcome_node: welcome_node,
         coordinator_node: coordinator_node,
         storage_nodes: storage_nodes
       }}
    end

    test "should retrieve the missing beacon summaries from the given date" do
      Crypto.generate_deterministic_keypair("daily_nonce_seed")
      |> elem(0)
      |> NetworkLookup.set_daily_nonce_public_key(DateTime.utc_now() |> DateTime.add(-10))

      inputs = [
        %TransactionInput{
          from: "@Alice2",
          amount: 1_000_000_000,
          spent?: true,
          type: :UCO,
          timestamp: DateTime.utc_now()
        }
      ]

      tx = TransactionFactory.create_valid_transaction(inputs)

      me = self()

      MockDB
      |> stub(:write_transaction, fn ^tx, _ ->
        send(me, :storage)
        :ok
      end)

      tx_summary = TransactionSummary.from_transaction(tx)

      elected_storage_nodes =
        Election.chain_storage_nodes(tx.address, P2P.authorized_and_available_nodes())

      welcome_node_keypair = Crypto.derive_keypair("welcome_node", 0)
      storage_node_keypair1 = Crypto.derive_keypair("node_keypair", 1)
      storage_node_keypair2 = Crypto.derive_keypair("node_keypair", 2)

      summary = %BeaconSummary{
        subset: <<0>>,
        summary_time: DateTime.utc_now(),
        transaction_attestations: [
          %ReplicationAttestation{
            transaction_summary: tx_summary,
            confirmations:
              elected_storage_nodes
              |> Enum.map(fn node ->
                node_index = Enum.find_index(elected_storage_nodes, &(&1 == node))

                sig =
                  cond do
                    node.first_public_key == elem(welcome_node_keypair, 0) ->
                      Crypto.sign(
                        TransactionSummary.serialize(tx_summary),
                        elem(welcome_node_keypair, 1)
                      )

                    node.first_public_key == elem(storage_node_keypair1, 0) ->
                      Crypto.sign(
                        TransactionSummary.serialize(tx_summary),
                        elem(storage_node_keypair1, 1)
                      )

                    node.first_public_key == elem(storage_node_keypair2, 0) ->
                      Crypto.sign(
                        TransactionSummary.serialize(tx_summary),
                        elem(storage_node_keypair2, 1)
                      )

                    node.first_public_key == Crypto.first_node_public_key() ->
                      Crypto.sign_with_first_node_key(TransactionSummary.serialize(tx_summary))
                  end

                {node_index, sig}
              end)
          }
        ]
      }

      tx_address = tx.address

      MockClient
      |> stub(:send_message, fn
        _, %GetBeaconSummaries{}, _ ->
          {:ok, %BeaconSummaryList{summaries: [summary]}}

        _, %GetTransaction{address: ^tx_address}, _ ->
          {:ok, tx}

        _, %GetGenesisAddress{}, _ ->
          {:ok, %NotFound{}}
      end)

      MockDB
      |> stub(:register_stats, fn _, _, _, _ -> :ok end)

      assert :ok = Sync.load_missed_transactions(DateTime.utc_now() |> DateTime.add(-86_400))

      assert_received :storage
    end
  end

  test "load_missed_transactions should postpone attestation if refused" do
    Crypto.generate_deterministic_keypair("daily_nonce_seed")
    |> elem(0)
    |> NetworkLookup.set_daily_nonce_public_key(DateTime.utc_now() |> DateTime.add(-10))

    # Summary timer each hour
    start_supervised!({BeaconSummaryTimer, interval: "0 0 * * * *"})
    start_supervised!({BeaconSlotTimer, interval: "0 */10 * * * *"})
    # Create 11 nodes on last summary
    nodes_keypair =
      Enum.map(0..10, fn i ->
        node_keypair = Crypto.derive_keypair("node_seed#{i}", 1)

        P2P.add_and_connect_node(%Node{
          ip: {88, 130, 19, i},
          port: 3000 + i,
          last_public_key: elem(node_keypair, 0),
          first_public_key: elem(node_keypair, 0),
          geo_patch: "BBB",
          network_patch: "BBB",
          available?: true,
          authorized?: true,
          authorization_date: DateTime.utc_now() |> DateTime.add(-1, :hour),
          enrollment_date: DateTime.utc_now() |> DateTime.add(-2, :hour)
        })

        node_keypair
      end)

    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      authorization_date: DateTime.utc_now() |> DateTime.add(-1, :hour),
      enrollment_date: DateTime.utc_now() |> DateTime.add(-2, :hour)
    })

    tx_timestamp = DateTime.utc_now() |> DateTime.add(-59, :minute)

    tx1 =
      TransactionFactory.create_valid_transaction([],
        timestamp: tx_timestamp
      )

    tx1_summary = TransactionSummary.from_transaction(tx1)

    elected_storage_nodes =
      Election.chain_storage_nodes(tx1.address, P2P.authorized_and_available_nodes(tx_timestamp))

    # First Replication with enough threshold
    attestation1 = %ReplicationAttestation{
      transaction_summary: tx1_summary,
      confirmations:
        Enum.map(0..3, fn i ->
          node = Enum.at(elected_storage_nodes, i)

          signature =
            if node.first_public_key == Crypto.first_node_public_key() do
              tx1_summary
              |> TransactionSummary.serialize()
              |> Crypto.sign_with_first_node_key()
            else
              node_private_key =
                Enum.find_value(
                  nodes_keypair,
                  &if(elem(&1, 0) == node.first_public_key, do: elem(&1, 1))
                )

              tx1_summary |> TransactionSummary.serialize() |> Crypto.sign(node_private_key)
            end

          index =
            ReplicationAttestation.get_node_index(node.first_public_key, tx1_summary.timestamp)

          {index, signature}
        end)
    }

    tx2 =
      TransactionFactory.create_valid_transaction([],
        index: 1,
        timestamp: DateTime.utc_now() |> DateTime.add(-59, :minute)
      )

    tx2_summary = TransactionSummary.from_transaction(tx2)

    elected_storage_nodes =
      Election.chain_storage_nodes(tx2.address, P2P.authorized_and_available_nodes())

    # Second Replication without enough threshold
    attestation2 = %ReplicationAttestation{
      transaction_summary: tx2_summary,
      confirmations:
        Enum.map(0..1, fn i ->
          node = Enum.at(elected_storage_nodes, i)

          signature =
            if node.first_public_key == Crypto.first_node_public_key() do
              tx2_summary
              |> TransactionSummary.serialize()
              |> Crypto.sign_with_first_node_key()
            else
              node_private_key =
                Enum.find_value(
                  nodes_keypair,
                  &if(elem(&1, 0) == node.first_public_key, do: elem(&1, 1))
                )

              tx2_summary |> TransactionSummary.serialize() |> Crypto.sign(node_private_key)
            end

          index =
            ReplicationAttestation.get_node_index(node.first_public_key, tx2_summary.timestamp)

          {index, signature}
        end)
    }

    attestations = [attestation1, attestation2]

    summary_time = DateTime.utc_now() |> BeaconSummaryTimer.previous_summary()

    PubSub.register_to_new_replication_attestations()

    summary = %BeaconSummary{
      subset: <<0>>,
      summary_time: summary_time,
      transaction_attestations: attestations
    }

    tx1_address = tx1.address
    tx2_address = tx2.address

    me = self()

    MockClient
    |> stub(:send_message, fn
      _, %GetBeaconSummaries{}, _ ->
        {:ok, %BeaconSummaryList{summaries: [summary]}}

      _, %GetTransaction{address: ^tx1_address}, _ ->
        send(me, :should_request)
        {:ok, tx1}

      _, %GetTransaction{address: ^tx2_address}, _ ->
        send(me, :should_not_request)
        {:ok, tx2}

      _, %GetTransaction{address: _}, _ ->
        {:ok, %NotFound{}}

      _, %GetTransactionChain{}, _ ->
        {:ok, %TransactionList{transactions: []}}

      _, %GetGenesisAddress{}, _ ->
        {:ok, %NotFound{}}
    end)

    Sync.load_missed_transactions(DateTime.utc_now() |> DateTime.add(-1, :hour))

    assert_receive {:new_replication_attestation, ^attestation2}
    assert_receive :should_request
    refute_receive {:new_replication_attestation, ^attestation1}
    refute_receive :should_not_request
  end

  describe "process_summary_aggregate/2" do
    setup do
      start_supervised!({BeaconSlotTimer, [interval: "* * * * * *"]})
      start_supervised!({BeaconSummaryTimer, [interval: "0 * * * * *"]})
      :ok
    end

    test "should synchronize transactions" do
      create_p2p_context()

      inputs = [
        %TransactionInput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now()
        }
      ]

      transfer_tx =
        TransactionFactory.create_valid_transaction(inputs,
          seed: "transfer_seed"
        )

      tx_address = transfer_tx.address
      me = self()

      MockDB
      |> stub(:write_transaction, fn ^transfer_tx, _ ->
        send(me, :transaction_stored)
        :ok
      end)

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{address: ^tx_address}, _ ->
          {:ok, transfer_tx}

        _, %GetTransaction{address: _}, _ ->
          {:ok, %NotFound{}}

        _, %GetGenesisAddress{}, _ ->
          {:ok, %NotFound{}}
      end)

      MockDB
      |> stub(:register_stats, fn _, _, _, _ ->
        :ok
      end)

      tx_summary = TransactionSummary.from_transaction(transfer_tx)

      index =
        ReplicationAttestation.get_node_index(
          Crypto.first_node_public_key(),
          tx_summary.timestamp
        )

      signature =
        tx_summary |> TransactionSummary.serialize() |> Crypto.sign_with_first_node_key()

      assert :ok =
               Sync.process_summary_aggregate(
                 %SummaryAggregate{
                   summary_time: DateTime.utc_now(),
                   replication_attestations: [
                     %ReplicationAttestation{
                       transaction_summary: tx_summary,
                       confirmations: [{index, signature}]
                     }
                   ],
                   availability_adding_time: 10
                 },
                 P2P.authorized_and_available_nodes()
               )

      assert_received :transaction_stored
    end
  end

  defp create_p2p_context do
    pb_key1 = Crypto.derive_keypair("key11", 0) |> elem(0)
    pb_key3 = Crypto.derive_keypair("key33", 0) |> elem(0)

    welcome_node = %Node{
      first_public_key: pb_key1,
      last_public_key: pb_key1,
      available?: true,
      geo_patch: "BBB",
      network_patch: "BBB",
      authorized?: true,
      reward_address: Crypto.derive_address(pb_key1),
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      enrollment_date: DateTime.utc_now()
    }

    coordinator_node = %Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA",
      reward_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      enrollment_date: DateTime.utc_now()
    }

    storage_nodes = [
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: pb_key3,
        last_public_key: pb_key3,
        geo_patch: "BBB",
        network_patch: "BBB",
        reward_address: Crypto.derive_address(pb_key3),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-10),
        enrollment_date: DateTime.utc_now()
      }
    ]

    Enum.each(storage_nodes, &P2P.add_and_connect_node(&1))

    P2P.add_and_connect_node(welcome_node)
    P2P.add_and_connect_node(coordinator_node)
  end
end
