defmodule Archethic.ReplicationTransactionPoolTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ProofOfValidation
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.Replication.TransactionPool

  alias Archethic.TransactionFactory

  test "add_transaction/2 should add transaction in the pool" do
    {:ok, pid} = TransactionPool.start_link([clean_interval: 0], [])

    tx = %Transaction{address: address} = TransactionFactory.create_valid_transaction()

    inputs = [
      %UnspentOutput{
        from: ArchethicCase.random_address(),
        amount: 100_000_000,
        type: :UCO
      }
      |> VersionedUnspentOutput.wrap_unspent_output(current_protocol_version())
    ]

    now = DateTime.utc_now()
    TransactionPool.add_transaction(pid, tx, inputs)

    assert %{transactions: %{^address => {^tx, expire_at, ^inputs}}} = :sys.get_state(pid)

    assert DateTime.diff(expire_at, now, :second) == 60
  end

  describe "get_transaction/2" do
    test "should get and let a registered transaction in the pool" do
      {:ok, pid} = TransactionPool.start_link([clean_interval: 0], [])

      tx = %Transaction{address: address} = TransactionFactory.create_valid_transaction()

      inputs = [
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{from: random_address(), amount: 100_000_000, type: :UCO}
        }
      ]

      TransactionPool.add_transaction(pid, tx, inputs)

      assert {:ok, ^tx, ^inputs} = TransactionPool.get_transaction(pid, address)

      assert %{transactions: %{^address => {^tx, _, ^inputs}}} = :sys.get_state(pid)
    end
  end

  describe "pop_transaction/2" do
    test "should get and remove a registered transaction in the pool" do
      {:ok, pid} = TransactionPool.start_link([clean_interval: 0], [])

      tx = %Transaction{address: address} = TransactionFactory.create_valid_transaction()

      inputs = [
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{from: random_address(), amount: 100_000_000, type: :UCO}
        }
      ]

      TransactionPool.add_transaction(pid, tx, inputs)

      assert {:ok, ^tx, ^inputs} = TransactionPool.pop_transaction(pid, address)

      assert %{transactions: %{}} = :sys.get_state(pid)
    end
  end

  test "add_proof_of_validation/3 should add the proof of validation to registered transaction in the pool" do
    {:ok, pid} = TransactionPool.start_link([clean_interval: 0], [])

    tx = %Transaction{address: address} = TransactionFactory.create_valid_transaction()

    {proof = %ProofOfValidation{}, tx_without_proof} =
      Map.get_and_update!(tx, :proof_of_validation, fn proof -> {proof, nil} end)

    inputs = [
      %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{from: random_address(), amount: 100_000_000, type: :UCO}
      }
    ]

    TransactionPool.add_transaction(pid, tx_without_proof, inputs)

    assert {:ok, ^tx_without_proof, ^inputs} = TransactionPool.get_transaction(pid, address)

    assert :ok = TransactionPool.add_proof_of_validation(pid, proof, address)

    assert {:ok, ^tx, ^inputs} = TransactionPool.get_transaction(pid, address)
  end

  test "should clean too long transactions" do
    {:ok, pid} = TransactionPool.start_link([clean_interval: 1000, ttl: 500], [])
    address = :crypto.strong_rand_bytes(33)

    TransactionPool.add_transaction(pid, %Transaction{address: address, type: :transfer}, [
      %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          from: ArchethicCase.random_address(),
          amount: 100_000_000,
          type: :UCO
        }
      }
    ])

    Process.sleep(1200)
    assert %{transactions: %{}} = :sys.get_state(pid)
  end
end
