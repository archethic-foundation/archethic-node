defmodule Archethic.SelfRepair.Sync.TransactionHandlerTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Archethic.BeaconChain.Subset, as: BeaconSubset

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetGenesisAddress
  alias Archethic.P2P.Message.GetTransactionInputs
  alias Archethic.P2P.Message.GenesisAddress
  alias Archethic.P2P.Message.TransactionInputList
  alias Archethic.P2P.Node

  alias Archethic.SelfRepair
  alias Archethic.SelfRepair.Sync.TransactionHandler
  alias Archethic.SharedSecrets.MemTables.NetworkLookup

  alias Archethic.TransactionFactory

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.TransactionChain.VersionedTransactionInput

  doctest TransactionHandler

  import Mox
  import Mock

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

  describe "download_transaction?/2" do
    test "should return true when the node is a chain storage node" do
      nodes = [P2P.get_node_info() | P2P.authorized_and_available_nodes()] |> P2P.distinct_nodes()

      attestation = %ReplicationAttestation{
        transaction_summary: %TransactionSummary{
          address: "@Alice2",
          version: 1,
          genesis_address: "@Alice0"
        }
      }

      assert true =
               TransactionHandler.download_transaction?(
                 attestation,
                 nodes
               )
    end

    test "should return true when the node only a chain genesis storage node" do
      with_mock(Election, [:passthrough],
        chain_storage_node?: fn
          "@Alice1", _, _ -> false
          "@Alice0", _, _ -> true
        end
      ) do
        attestation = %ReplicationAttestation{
          transaction_summary: %TransactionSummary{
            address: "@Alice1",
            genesis_address: "@Alice0"
          }
        }

        assert true =
                 TransactionHandler.download_transaction?(
                   attestation,
                   []
                 )
      end
    end

    test "should return true when the node only a I/O storage node" do
      with_mock(Election, [:passthrough],
        chain_storage_nodes: fn
          "@Bob3", _ ->
            [%Node{first_public_key: Crypto.first_node_public_key()}]

          _, _ ->
            [%Node{first_public_key: ArchethicCase.random_public_key()}]
        end
      ) do
        attestation = %ReplicationAttestation{
          transaction_summary: %TransactionSummary{
            address: "@Alice1",
            genesis_address: "@Alice0",
            movements_addresses: ["@Bob3"]
          }
        }

        node_list = [
          %Node{
            first_public_key: Crypto.first_node_public_key(),
            geo_patch: "AAA",
            network_patch: "AAA"
          }
        ]

        assert true =
                 TransactionHandler.download_transaction?(
                   attestation,
                   node_list
                 )
      end
    end

    test "should return true when the node only a genesis I/O storage node without genesis fetching" do
      with_mock(Election, [:passthrough],
        chain_storage_nodes: fn
          "@Bob0", _ ->
            [%Node{first_public_key: Crypto.first_node_public_key(), network_patch: "AAA"}]

          _, _ ->
            [%Node{first_public_key: ArchethicCase.random_public_key(), network_patch: "AAA"}]
        end
      ) do
        attestation = %ReplicationAttestation{
          transaction_summary: %TransactionSummary{
            address: "@Alice1",
            genesis_address: "@Alice0",
            movements_addresses: ["@Bob0"]
          }
        }

        node_list = [
          %Node{
            first_public_key: Crypto.first_node_public_key(),
            geo_patch: "AAA",
            network_patch: "AAA"
          }
        ]

        assert true =
                 TransactionHandler.download_transaction?(
                   attestation,
                   node_list
                 )
      end
    end

    test "should return true when the node only a genesis I/O storage node with genesis fetching" do
      MockClient
      |> stub(:send_message, fn _, %GetGenesisAddress{address: "@Bob3"}, _ ->
        {:ok, %GenesisAddress{address: "@Bob0", timestamp: DateTime.utc_now()}}
      end)

      with_mock(Election, [:passthrough],
        chain_storage_nodes: fn
          "@Bob0", _ ->
            [%Node{first_public_key: Crypto.first_node_public_key(), network_patch: "AAA"}]

          _, _ ->
            [%Node{first_public_key: ArchethicCase.random_public_key(), network_patch: "AAA"}]
        end
      ) do
        attestation = %ReplicationAttestation{
          transaction_summary: %TransactionSummary{
            address: "@Alice1",
            genesis_address: "@Alice0",
            movements_addresses: ["@Bob3"],
            version: 1
          }
        }

        node_list = [
          %Node{
            first_public_key: Crypto.first_node_public_key(),
            geo_patch: "AAA",
            network_patch: "AAA"
          }
        ]

        assert true =
                 TransactionHandler.download_transaction?(
                   attestation,
                   node_list
                 )
      end
    end
  end

  describe "download_transaction_data/4" do
    test "should download the transaction and the inputs" do
      inputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now()
        }
      ]

      tx = TransactionFactory.create_valid_transaction(inputs)

      inputs = [
        %VersionedTransactionInput{
          protocol_version: current_protocol_version(),
          input: %TransactionInput{
            from: random_address(),
            type: :UCO,
            amount: 1,
            timestamp: DateTime.utc_now()
          }
        }
      ]

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{}, _ ->
          {:ok, tx}

        _, %GetTransactionInputs{}, _ ->
          {:ok, %TransactionInputList{inputs: inputs, more?: false, offset: 0}}
      end)

      attestation = %ReplicationAttestation{
        transaction_summary:
          TransactionSummary.from_transaction(tx, Transaction.previous_address(tx))
      }

      assert {^tx, ^inputs} =
               TransactionHandler.download_transaction_data(
                 attestation,
                 P2P.authorized_and_available_nodes(),
                 Crypto.first_node_public_key(),
                 BeaconChain.previous_summary_time(DateTime.utc_now())
               )
    end

    test "should be able to download the transaction even if there are split",
         %{
           welcome_node: welcome_node,
           coordinator_node: coordinator_node,
           storage_nodes: storage_nodes
         } do
      inputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now()
        }
      ]

      welcome_node_pkey = welcome_node.first_public_key
      coordinator_node_pkey = coordinator_node.first_public_key
      storage_node_pkey = Enum.at(storage_nodes, 0).first_public_key

      tx = TransactionFactory.create_valid_transaction(inputs)

      MockClient
      |> stub(:send_message, fn
        %Node{first_public_key: ^welcome_node_pkey}, %GetTransaction{}, _ ->
          {:ok, tx}

        %Node{first_public_key: ^coordinator_node_pkey}, %GetTransaction{}, _ ->
          # split
          {:ok, %Transaction{tx | type: :data}}

        %Node{first_public_key: ^storage_node_pkey}, %GetTransaction{}, _ ->
          # split
          {:ok, %Transaction{tx | type: :data}}

        _, %GetTransactionInputs{}, _ ->
          {:ok, %TransactionInputList{inputs: [], more?: false, offset: 0}}
      end)

      assert {^tx, []} =
               TransactionHandler.download_transaction_data(
                 %ReplicationAttestation{
                   transaction_summary:
                     TransactionSummary.from_transaction(tx, Transaction.previous_address(tx))
                 },
                 P2P.authorized_and_available_nodes(),
                 Crypto.first_node_public_key(),
                 BeaconChain.previous_summary_time(DateTime.utc_now())
               )
    end

    test "should raise an error if no one has the expected transaction",
         %{
           welcome_node: welcome_node,
           coordinator_node: coordinator_node,
           storage_nodes: storage_nodes
         } do
      inputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now()
        }
      ]

      welcome_node_pkey = welcome_node.first_public_key
      coordinator_node_pkey = coordinator_node.first_public_key
      storage_node_pkey = Enum.at(storage_nodes, 0).first_public_key

      tx = TransactionFactory.create_valid_transaction(inputs)

      MockClient
      |> stub(:send_message, fn
        %Node{first_public_key: ^welcome_node_pkey}, %GetTransaction{}, _ ->
          # split
          {:ok, %Transaction{tx | type: :data}}

        %Node{first_public_key: ^coordinator_node_pkey}, %GetTransaction{}, _ ->
          # split
          {:ok, %Transaction{tx | type: :data}}

        %Node{first_public_key: ^storage_node_pkey}, %GetTransaction{}, _ ->
          # split
          {:ok, %Transaction{tx | type: :data}}

        _, %GetTransactionInputs{}, _ ->
          {:ok, %TransactionInputList{inputs: [], more?: false, offset: 0}}
      end)

      attestation = %ReplicationAttestation{
        transaction_summary:
          TransactionSummary.from_transaction(tx, Transaction.previous_address(tx))
      }

      message =
        "Self repair encounter an error in function download_transaction_data on address: #{Base.encode16(tx.address)} with error Cannot fetch the transaction to sync because of :acceptance_failed"

      assert_raise SelfRepair.Error, message, fn ->
        TransactionHandler.download_transaction_data(
          attestation,
          P2P.authorized_and_available_nodes(),
          Crypto.first_node_public_key(),
          BeaconChain.previous_summary_time(DateTime.utc_now())
        )
      end
    end

    test "should raise an error if the downloaded transaction is not the expected one" do
      inputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now()
        }
      ]

      tx = TransactionFactory.create_valid_transaction(inputs)

      modified_tx = %{tx | type: :oracle}

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{}, _ ->
          {:ok, modified_tx}

        _, %GetTransactionInputs{}, _ ->
          {:ok, %TransactionInputList{inputs: [], more?: false, offset: 0}}
      end)

      attestation = %ReplicationAttestation{
        transaction_summary:
          TransactionSummary.from_transaction(tx, Transaction.previous_address(tx))
      }

      message =
        "Self repair encounter an error in function download_transaction_data on address: #{Base.encode16(tx.address)} with error Cannot fetch the transaction to sync because of :acceptance_failed"

      assert_raise SelfRepair.Error, message, fn ->
        TransactionHandler.download_transaction_data(
          attestation,
          P2P.authorized_and_available_nodes(),
          Crypto.first_node_public_key(),
          BeaconChain.previous_summary_time(DateTime.utc_now())
        )
      end
    end

    test "should download the transaction even after a first failure" do
      inputs = [
        %UnspentOutput{
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
        _, %GetTransaction{}, _ -> {:error, :network_issue}
      end)
      |> expect(:send_message, fn
        _, %GetTransaction{}, _ -> {:ok, tx}
      end)

      attestation = %ReplicationAttestation{
        transaction_summary:
          TransactionSummary.from_transaction(tx, Transaction.previous_address(tx))
      }

      with_mock(Election, [:passthrough], chain_storage_node?: fn _, _, _, _ -> false end) do
        assert {^tx, []} =
                 TransactionHandler.download_transaction_data(
                   attestation,
                   P2P.authorized_and_available_nodes(),
                   Crypto.first_node_public_key(),
                   BeaconChain.previous_summary_time(DateTime.utc_now())
                 )
      end
    end
  end

  describe "process_transaction_data/5" do
    test "should handle the transaction and replicate it" do
      me = self()

      inputs = [
        %VersionedTransactionInput{
          input: %UnspentOutput{
            from: "@Alice2",
            amount: 1_000_000_000,
            type: :UCO,
            timestamp: DateTime.utc_now()
          },
          protocol_version: current_protocol_version()
        }
      ]

      tx = TransactionFactory.create_valid_transaction()

      MockDB
      |> stub(:write_transaction, fn ^tx, _ ->
        send(me, :transaction_replicated)
        :ok
      end)
      |> stub(:list_io_transactions, fn _fields -> [] end)
      |> stub(:list_transactions, fn _fields -> [] end)

      MockTransactionLedger
      |> expect(:write_inputs, fn _, ^inputs ->
        send(me, :transaction_inputs_writed)
        :ok
      end)

      tx_summary = TransactionSummary.from_transaction(tx, Transaction.previous_address(tx))

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
               TransactionHandler.process_transaction_data(
                 attestation,
                 tx,
                 inputs,
                 P2P.authorized_and_available_nodes(),
                 Crypto.first_node_public_key()
               )

      assert_receive :transaction_replicated
      assert_receive :transaction_inputs_writed
    end

    test "should handle the transaction and replicate it on attestation V1" do
      P2P.add_and_connect_node(%Node{
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        authorized?: true,
        available?: true,
        authorization_date: ~U[2022-01-01 00:00:00.000Z],
        geo_patch: "AAA",
        network_patch: "AAA",
        reward_address: :crypto.strong_rand_bytes(32),
        enrollment_date: ~U[2022-01-01 00:00:00.000Z]
      })

      me = self()

      inputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: ~U[2022-01-02 00:00:00.000Z]
        }
      ]

      tx =
        TransactionFactory.create_valid_transaction(inputs,
          timestamp: ~U[2022-01-02 00:00:00.000Z]
        )

      MockDB
      |> stub(:write_transaction, fn ^tx, _ ->
        send(me, :transaction_replicated)
        :ok
      end)
      |> stub(:list_io_transactions, fn _fields -> [] end)
      |> stub(:list_transactions, fn _fields -> [] end)

      tx_summary = TransactionSummary.from_transaction(tx, Transaction.previous_address(tx))

      attestation = %ReplicationAttestation{
        version: 1,
        transaction_summary: tx_summary
      }

      assert :ok =
               TransactionHandler.process_transaction_data(
                 attestation,
                 tx,
                 [],
                 P2P.authorized_and_available_nodes(),
                 Crypto.first_node_public_key()
               )

      assert_receive :transaction_replicated
    end

    test "should raise an error if transaction is invalid on attestation V1" do
      P2P.add_and_connect_node(%Node{
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        authorized?: true,
        available?: true,
        authorization_date: ~U[2022-01-01 00:00:00.000Z],
        geo_patch: "AAA",
        network_patch: "AAA",
        reward_address: :crypto.strong_rand_bytes(32),
        enrollment_date: ~U[2022-01-01 00:00:00.000Z]
      })

      inputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: ~U[2022-01-02 00:00:00.000Z]
        }
      ]

      tx =
        TransactionFactory.create_transaction_with_invalid_validation_stamp_signature(inputs,
          timestamp: ~U[2022-01-02 00:00:00.000Z]
        )

      tx_summary = TransactionSummary.from_transaction(tx, Transaction.previous_address(tx))

      attestation = %ReplicationAttestation{
        version: 1,
        transaction_summary: tx_summary
      }

      message =
        "Self repair encounter an error in function verify_transaction on address: #{Base.encode16(tx.address)} with error Transaction signature error in self repair"

      assert_raise SelfRepair.Error, message, fn ->
        TransactionHandler.process_transaction_data(
          attestation,
          tx,
          [],
          P2P.authorized_and_available_nodes(),
          Crypto.first_node_public_key()
        )
      end
    end

    test "should handle raise an error when attestation is invalid" do
      inputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now()
        }
      ]

      tx = TransactionFactory.create_valid_transaction(inputs)

      tx_summary = TransactionSummary.from_transaction(tx, Transaction.previous_address(tx))

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

      assert_raise SelfRepair.Error, fn ->
        TransactionHandler.process_transaction_data(
          attestation,
          tx,
          [],
          P2P.authorized_and_available_nodes(),
          Crypto.first_node_public_key()
        )
      end
    end
  end
end
