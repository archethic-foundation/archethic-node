defmodule Archethic.SelfRepair.Sync.TransactionHandlerTest do
  use ArchethicCase

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Archethic.BeaconChain.Subset, as: BeaconSubset

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Node

  alias Archethic.SelfRepair.Sync.TransactionHandler
  alias Archethic.SharedSecrets.MemTables.NetworkLookup

  alias Archethic.TransactionFactory

  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.TransactionSummary

  doctest TransactionHandler

  import Mox

  setup do
    start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *"})
    Enum.each(BeaconChain.list_subsets(), &BeaconSubset.start_link(subset: &1))
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
      reward_address: :crypto.strong_rand_bytes(32),
      enrollment_date: DateTime.utc_now()
    }

    storage_nodes = [
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
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

    Crypto.generate_deterministic_keypair("daily_nonce_seed")
    |> elem(0)
    |> NetworkLookup.set_daily_nonce_public_key(DateTime.utc_now() |> DateTime.add(-10))

    {:ok,
     %{
       welcome_node: welcome_node,
       coordinator_node: coordinator_node,
       storage_nodes: storage_nodes
     }}
  end

  test "download_transaction?/1 should return true when the node is a chain storage node" do
    nodes = [P2P.get_node_info() | P2P.authorized_and_available_nodes()] |> P2P.distinct_nodes()

    attestation = %ReplicationAttestation{
      transaction_summary: %TransactionSummary{address: "@Alice2"}
    }

    assert true =
             TransactionHandler.download_transaction?(
               attestation,
               nodes
             )
  end

  test "download_transaction/2 should download the transaction" do
    inputs = [
      %TransactionInput{
        from: "@Alice2",
        amount: 1_000_000_000,
        type: :UCO,
        timestamp: DateTime.utc_now()
      }
    ]

    tx = TransactionFactory.create_valid_transaction(inputs)

    MockClient
    |> stub(:send_message, fn
      _, %GetTransaction{}, _ ->
        {:ok, tx}
    end)

    attestation = %ReplicationAttestation{
      transaction_summary: TransactionSummary.from_transaction(tx)
    }

    assert ^tx =
             TransactionHandler.download_transaction(
               attestation,
               P2P.authorized_and_available_nodes()
             )
  end

  test "download_transaction/2 should raise an error if the downloaded transaction is not the expected one" do
    inputs = [
      %TransactionInput{
        from: "@Alice2",
        amount: 1_000_000_000,
        type: :UCO,
        timestamp: DateTime.utc_now()
      }
    ]

    tx = TransactionFactory.create_valid_transaction(inputs)

    modified_tx = %{tx | address: "@Bob"}

    MockClient
    |> stub(:send_message, fn
      _, %GetTransaction{}, _ ->
        {:ok, modified_tx}
    end)

    attestation = %ReplicationAttestation{
      transaction_summary: TransactionSummary.from_transaction(tx)
    }

    message = "Transaction downloaded is different than expected"

    assert_raise RuntimeError, message, fn ->
      TransactionHandler.download_transaction(
        attestation,
        P2P.authorized_and_available_nodes()
      )
    end
  end

  test "download_transaction/2 should download the transaction even after a first failure" do
    inputs = [
      %TransactionInput{
        from: "@Alice2",
        amount: 1_000_000_000,
        type: :UCO,
        timestamp: DateTime.utc_now()
      }
    ]

    tx = TransactionFactory.create_valid_transaction(inputs)

    pb_key1 = Crypto.derive_keypair("key101", 0) |> elem(0)
    pb_key2 = Crypto.derive_keypair("key202", 0) |> elem(0)
    pb_key3 = Crypto.derive_keypair("key303", 0) |> elem(0)

    nodes = [
      %Node{
        first_public_key: pb_key1,
        last_public_key: pb_key1,
        authorized?: true,
        available?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-10),
        geo_patch: "AAA",
        network_patch: "AAA",
        reward_address: :crypto.strong_rand_bytes(32),
        enrollment_date: DateTime.utc_now()
      },
      %Node{
        first_public_key: pb_key2,
        last_public_key: pb_key2,
        authorized?: true,
        available?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-10),
        geo_patch: "AAA",
        network_patch: "AAA",
        reward_address: :crypto.strong_rand_bytes(32),
        enrollment_date: DateTime.utc_now()
      },
      %Node{
        first_public_key: pb_key3,
        last_public_key: pb_key3,
        authorized?: true,
        available?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-10),
        geo_patch: "AAA",
        network_patch: "AAA",
        reward_address: :crypto.strong_rand_bytes(32),
        enrollment_date: DateTime.utc_now()
      }
    ]

    Enum.each(nodes, &P2P.add_and_connect_node(&1))

    MockClient
    |> expect(:send_message, 4, fn
      _, %GetTransaction{}, _ ->
        {:error, :network_issue}
    end)
    |> expect(:send_message, fn
      _, %GetTransaction{}, _ ->
        {:ok, tx}
    end)

    attestation = %ReplicationAttestation{
      transaction_summary: TransactionSummary.from_transaction(tx)
    }

    assert ^tx =
             TransactionHandler.download_transaction(
               attestation,
               P2P.authorized_and_available_nodes()
             )
  end

  test "process_transaction/3 should handle the transaction and replicate it" do
    me = self()

    inputs = [
      %TransactionInput{
        from: "@Alice2",
        amount: 1_000_000_000,
        type: :UCO,
        timestamp: DateTime.utc_now()
      }
    ]

    tx = TransactionFactory.create_valid_transaction(inputs)

    MockDB
    |> stub(:write_transaction, fn ^tx, _ ->
      send(me, :transaction_replicated)
      :ok
    end)

    tx_summary = TransactionSummary.from_transaction(tx)

    index =
      ReplicationAttestation.get_node_index(
        Crypto.first_node_public_key(),
        tx_summary.timestamp
      )

    signature =
      tx_summary
      |> TransactionSummary.serialize()
      |> Crypto.sign_with_first_node_key()

    attestation = %ReplicationAttestation{
      transaction_summary: tx_summary,
      confirmations: [{index, signature}]
    }

    assert :ok =
             TransactionHandler.process_transaction(
               attestation,
               tx,
               P2P.authorized_and_available_nodes()
             )

    assert_received :transaction_replicated
  end

  test "process_transaction/3 should handle raise an error when attestation is invalid" do
    inputs = [
      %TransactionInput{
        from: "@Alice2",
        amount: 1_000_000_000,
        type: :UCO,
        timestamp: DateTime.utc_now()
      }
    ]

    tx = TransactionFactory.create_valid_transaction(inputs)

    tx_summary = TransactionSummary.from_transaction(tx)

    index =
      ReplicationAttestation.get_node_index(
        Crypto.first_node_public_key(),
        tx_summary.timestamp
      )

    signature =
      tx_summary
      |> TransactionSummary.serialize()
      |> Crypto.sign(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>)

    attestation = %ReplicationAttestation{
      transaction_summary: tx_summary,
      confirmations: [{index, signature}]
    }

    message = "Attestation error in self repair"

    assert_raise RuntimeError, message, fn ->
      TransactionHandler.process_transaction(
        attestation,
        tx,
        P2P.authorized_and_available_nodes()
      )
    end
  end
end
