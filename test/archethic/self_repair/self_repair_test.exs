defmodule Archethic.SelfRepairTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.ReplicationAttestation

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Client.DefaultImpl
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetNextAddresses
  alias Archethic.P2P.Message.GetTransaction

  alias Archethic.Replication
  alias Archethic.SelfRepair
  alias Archethic.SelfRepair.Sync.TransactionHandler

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.TransactionFactory

  import ArchethicCase
  import Mox
  import Mock

  doctest SelfRepair

  setup do
    :ok
  end

  test "update_last_address/1 should request missing addresses and add them in DB" do
    node = %Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      geo_patch: "AAA",
      authorized?: true,
      authorization_date: ~U[2022-11-27 00:00:00Z],
      available?: true
    }

    me = self()

    MockDB
    |> expect(:get_last_chain_address, fn "Alice2" -> {"Alice2", ~U[2022-11-27 00:10:00Z]} end)
    |> expect(:get_transaction, fn "Alice2", _, _ ->
      {:ok, %Transaction{validation_stamp: %ValidationStamp{timestamp: ~U[2022-11-27 00:10:00Z]}}}
    end)
    |> expect(:get_genesis_address, 2, fn "Alice2" -> "Alice0" end)
    |> expect(:list_chain_addresses, fn "Alice0" ->
      [
        {"Alice1", ~U[2022-11-27 00:09:00Z]},
        {"Alice2", ~U[2022-11-27 00:10:00Z]},
        {"Alice3", ~U[2022-11-27 00:11:00Z]},
        {"Alice4", ~U[2022-11-27 00:12:00Z]}
      ]
    end)
    |> expect(:add_last_transaction_address, 2, fn
      "Alice0", "Alice3", ~U[2022-11-27 00:11:00Z] ->
        send(me, :add_alice3)

      "Alice0", "Alice4", ~U[2022-11-27 00:12:00Z] ->
        send(me, :add_alice4)
    end)

    MockClient
    |> expect(:send_message, fn node, msg = %GetNextAddresses{address: "Alice2"}, timeout ->
      send(me, :get_next_addresses)
      DefaultImpl.send_message(node, msg, timeout)
    end)

    SelfRepair.update_last_address("Alice2", [node])

    assert_receive :get_next_addresses
    assert_receive :add_alice3
    assert_receive :add_alice4
  end

  describe "replicate_transaction/2 (storage=chain)" do
    setup do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: ~U[2001-01-01 00:00:00Z]
      })
    end

    test "should replicate a new transaction" do
      tx = %Transaction{address: address} = TransactionFactory.create_valid_transaction()
      genesis_address = Transaction.previous_address(tx)

      input1 = %VersionedTransactionInput{
        protocol_version: Archethic.Mining.protocol_version(),
        input: %TransactionInput{
          from: random_address(),
          type: :UCO,
          timestamp: DateTime.utc_now()
        }
      }

      MockClient
      |> expect(:send_message, fn _, %GetTransaction{address: ^address}, _ -> {:ok, tx} end)

      with_mock(Replication, sync_transaction_chain: fn _, _, _, _ -> :ok end) do
        with_mock(
          TransactionChain,
          [:passthrough],
          fetch_inputs: fn _, _ -> [input1] end,
          write_inputs: fn _, _ -> :ok end
        ) do
          assert :ok = SelfRepair.replicate_transaction(address, genesis_address, true)

          assert_called(TransactionChain.fetch_inputs(address, :_))
          assert_called(TransactionChain.write_inputs(address, [input1]))
          assert_called(Replication.sync_transaction_chain(:_, genesis_address, :_, :_))
        end
      end
    end

    test "should not replicate an existing transaction" do
      address = random_address()

      MockDB
      |> expect(:transaction_exists?, fn _, _ -> true end)

      assert {:error, :transaction_already_exists} =
               SelfRepair.replicate_transaction(address, true)
    end
  end

  describe "replicate_transaction/2 (storage=io)" do
    setup do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: ~U[2001-01-01 00:00:00Z]
      })
    end

    test "should replicate a new transaction" do
      tx = %Transaction{address: address} = TransactionFactory.create_valid_transaction()
      genesis_address = Transaction.previous_address(tx)

      MockClient
      |> expect(:send_message, fn _, %GetTransaction{address: ^address}, _ -> {:ok, tx} end)

      with_mock(Replication, synchronize_io_transaction: fn _, _, _ -> :ok end) do
        assert :ok = SelfRepair.replicate_transaction(address, genesis_address, false)
        assert_called(Replication.synchronize_io_transaction(:_, genesis_address, :_))
      end
    end

    test "should not replicate an existing transaction" do
      address = random_address()

      MockDB
      |> expect(:transaction_exists?, fn _, _ -> true end)

      assert {:error, :transaction_already_exists} =
               SelfRepair.replicate_transaction(address, false)
    end
  end

  describe "synchronize_current_summary/0" do
    test "should be able to run when there's nothing to sync" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: ~U[2001-01-01 00:00:00Z]
      })

      with_mock(BeaconChain, [:passthrough],
        next_summary_date: fn _ -> DateTime.utc_now() end,
        fetch_current_summary_replication_attestations: fn -> [] end
      ) do
        with_mock(TransactionHandler, [:passthrough], []) do
          assert 0 = SelfRepair.synchronize_current_summary()

          assert_not_called(TransactionHandler.download_transaction(:_, :_))
        end
      end
    end

    test "should resync missed transactions" do
      now = DateTime.utc_now()

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: ~U[2001-01-01 00:00:00Z]
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3001,
        first_public_key: random_public_key(),
        last_public_key: random_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: ~U[2001-01-01 00:00:00Z]
      })

      replication_attestation1 = random_replication_attestation(now)
      replication_attestation2 = random_replication_attestation(now)
      replication_attestation3 = random_replication_attestation(now)

      with_mock(BeaconChain, [:passthrough],
        next_summary_date: fn _ -> now end,
        fetch_current_summary_replication_attestations: fn ->
          [
            replication_attestation1,
            replication_attestation2,
            replication_attestation3
          ]
        end
      ) do
        with_mock(TransactionHandler, [:passthrough],
          download_transaction_data: fn _, _, _, _ ->
            {%Transaction{address: replication_attestation1.transaction_summary.address}, []}
          end,
          process_transaction_data: fn _, _, _, _, _ -> :ok end
        ) do
          assert 3 = SelfRepair.synchronize_current_summary()

          assert_called(
            TransactionHandler.download_transaction_data(replication_attestation1, :_, :_, :_)
          )

          assert_called(
            TransactionHandler.download_transaction_data(replication_attestation2, :_, :_, :_)
          )

          assert_called(
            TransactionHandler.download_transaction_data(replication_attestation3, :_, :_, :_)
          )
        end
      end
    end

    test "should not resync a transaction already existing" do
      now = DateTime.utc_now()

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: ~U[2001-01-01 00:00:00Z]
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3001,
        first_public_key: random_public_key(),
        last_public_key: random_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: ~U[2001-01-01 00:00:00Z]
      })

      replication_attestation1 = random_replication_attestation(now)

      with_mock(BeaconChain, [:passthrough],
        next_summary_date: fn _ -> now end,
        fetch_current_summary_replication_attestations: fn ->
          [
            replication_attestation1
          ]
        end
      ) do
        with_mock(TransactionChain, [:passthrough], transaction_exists?: fn _ -> true end) do
          with_mock(TransactionHandler, [:passthrough],
            download_transaction_data: fn _, _, _, _ ->
              {%Transaction{address: replication_attestation1.transaction_summary.address}, []}
            end
          ) do
            assert 0 = SelfRepair.synchronize_current_summary()

            assert_not_called(
              TransactionHandler.download_transaction_data(replication_attestation1, :_, :_, :_)
            )
          end
        end
      end
    end
  end

  defp random_replication_attestation(datetime) do
    %ReplicationAttestation{
      version: 2,
      transaction_summary: %TransactionSummary{
        address: random_address(),
        type: :transfer,
        timestamp: datetime,
        fee: 10_000_000,
        validation_stamp_checksum: :crypto.strong_rand_bytes(32),
        genesis_address: random_address()
      },
      confirmations: Enum.map(0..9, &{&1, "signature#{&1}"})
    }
  end
end
