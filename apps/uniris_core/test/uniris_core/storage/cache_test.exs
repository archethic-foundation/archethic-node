defmodule UnirisCore.Storage.CacheTest do
  use UnirisCoreCase

  alias UnirisCore.Crypto

  alias UnirisCore.Mining.Context
  alias UnirisCore.Mining.Fee

  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node

  alias UnirisCore.Storage.Cache

  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.CrossValidationStamp
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Ledger
  alias UnirisCore.TransactionData.Ledger.Transfer
  alias UnirisCore.TransactionData.UCOLedger
  alias UnirisCore.TransactionInput

  describe "store_transaction/1" do
    test "should insert the transaction" do
      tx = Transaction.new(:node_shared_secrets, %TransactionData{})

      stamp =
        ValidationStamp.new(tx, %Context{}, "welcome_node_public_key", "coordinator_public_key", [
          "cross_validation_node_public_key"
        ])

      validated_tx = %{tx | validation_stamp: stamp}
      :ok = Cache.store_transaction(validated_tx)
      assert validated_tx == Cache.get_transaction(tx.address)
    end

    test "should index the transaction as node transaction" do
      tx = Transaction.new(:node, %TransactionData{})

      stamp =
        ValidationStamp.new(tx, %Context{}, "welcome_node_public_key", "coordinator_public_key", [
          "cross_validation_node_public_key"
        ])

      validated_tx = %{tx | validation_stamp: stamp}
      :ok = Cache.store_transaction(validated_tx)
      assert [validated_tx] == Cache.node_transactions()
    end

    test "should index the transaction as node shared secrets transaction" do
      tx = Transaction.new(:node_shared_secrets, %TransactionData{})

      stamp =
        ValidationStamp.new(tx, %Context{}, "welcome_node_public_key", "coordinator_public_key", [
          "cross_validation_node_public_key"
        ])

      validated_tx = %{tx | validation_stamp: stamp}
      :ok = Cache.store_transaction(validated_tx)
      assert validated_tx == Cache.last_node_shared_secrets_transaction()

      tx2 = Transaction.new(:node_shared_secrets, %TransactionData{})

      stamp =
        ValidationStamp.new(
          tx2,
          %Context{},
          "welcome_node_public_key",
          "coordinator_public_key",
          ["cross_validation_node_public_key"]
        )

      validated_tx2 = %{tx2 | validation_stamp: stamp}
      :ok = Cache.store_transaction(validated_tx2)
      assert validated_tx2 == Cache.last_node_shared_secrets_transaction()
    end

    test "should set the ledger" do
      P2P.add_node(%Node{
        last_public_key: Crypto.node_public_key(),
        first_public_key: Crypto.node_public_key(),
        ip: {127, 0, 0, 1},
        port: 4000,
        ready?: true,
        available?: true
      })

      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{transfers: [%Transfer{to: "@Charlie5", amount: 3.0}]}
            }
          },
          "seed",
          0
        )

      :ets.insert(
        :uniris_ledger,
        {Crypto.hash(tx.previous_public_key),
         %UnspentOutput{
           amount: 10,
           from: :crypto.strong_rand_bytes(32)
         }, false}
      )

      stamp = %ValidationStamp{
        proof_of_work: "",
        proof_of_integrity: "",
        signature: "",
        ledger_operations: %LedgerOperations{
          fee: 0.5,
          node_movements:
            Fee.distribute(
              0.5,
              "welcome_node_public_key",
              "coordinator_public_key",
              ["cross_validator_public_key"],
              ["previous_storage_node_key"]
            ),
          transaction_movements: [
            %TransactionMovement{to: "@Charlie5", amount: 3.0}
          ],
          unspent_outputs: [
            %UnspentOutput{amount: 2.0, from: tx.address},
            %UnspentOutput{amount: 10, from: "@Bob3"}
          ]
        }
      }

      validated_tx = %{tx | validation_stamp: stamp}
      :ok = Cache.store_transaction(validated_tx)

      assert [
               %UnspentOutput{amount: 2.0, from: tx.address},
               %UnspentOutput{amount: 10.0, from: "@Bob3"}
             ] == Cache.get_unspent_outputs(tx.address)

      assert [
               %UnspentOutput{amount: 3.0, from: tx.address}
             ] == Cache.get_unspent_outputs("@Charlie5")

      welcome_node_address = "welcome_node_public_key" |> Crypto.hash()

      assert [
               %UnspentOutput{amount: 0.0025, from: tx.address}
             ] == Cache.get_unspent_outputs(welcome_node_address)

      coordinator_address = "coordinator_public_key" |> Crypto.hash()

      assert [
               %UnspentOutput{amount: 0.0475, from: tx.address}
             ] == Cache.get_unspent_outputs(coordinator_address)

      cross_validator_address = "cross_validator_public_key" |> Crypto.hash()

      assert [
               %UnspentOutput{amount: 0.2, from: tx.address}
             ] == Cache.get_unspent_outputs(cross_validator_address)

      previous_storage_node_address = "previous_storage_node_key" |> Crypto.hash()

      assert [
               %UnspentOutput{amount: 0.25, from: tx.address}
             ] == Cache.get_unspent_outputs(previous_storage_node_address)

      # assert [] == Cache.get_unspent_outputs(Crypto.hash(tx.previous_public_key))
    end
  end

  test "store_ko_transaction/1 should insert the transaction in the ko table" do
    tx = Transaction.new(:node_shared_secrets, %TransactionData{})

    tx = %{
      tx
      | cross_validation_stamps: [
          %CrossValidationStamp{
            signature: "signature",
            inconsistencies: [:invalid_proof_of_work],
            node_public_key: "node_public_key"
          }
        ]
    }

    :ok = Cache.store_ko_transaction(tx)
    assert true == Cache.ko_transaction?(tx.address)
  end

  test "last_transaction_address/1 should retrieve the last transaction on a chain" do
    tx1 = Transaction.new(:node, %TransactionData{}, "seed", 0)
    tx2 = Transaction.new(:node, %TransactionData{}, "seed", 1)
    tx3 = Transaction.new(:node, %TransactionData{}, "seed", 2)

    stamp =
      ValidationStamp.new(tx1, %Context{}, "welcome_node_public_key", "coordinator_public_key", [
        "cross_validation_node_public_key"
      ])

    validated_tx1 = %{tx1 | validation_stamp: stamp}
    Cache.store_transaction(validated_tx1)

    stamp =
      ValidationStamp.new(tx2, %Context{}, "welcome_node_public_key", "coordinator_public_key", [
        "cross_validation_node_public_key"
      ])

    validated_tx2 = %{tx2 | validation_stamp: stamp}
    Cache.store_transaction(validated_tx2)

    stamp =
      ValidationStamp.new(tx3, %Context{}, "welcome_node_public_key", "coordinator_public_key", [
        "cross_validation_node_public_key"
      ])

    validated_tx3 = %{tx3 | validation_stamp: stamp}
    Cache.store_transaction(validated_tx3)

    assert {:ok, tx3.address} == Cache.last_transaction_address(tx1.address)
    assert {:ok, tx3.address} == Cache.last_transaction_address(tx2.address)
    assert {:ok, tx3.address} == Cache.last_transaction_address(tx3.address)
  end

  test "list_transactions/1 should return a stream of transaction" do
    Enum.each(1..50, fn i ->
      tx = Transaction.new(:node, %TransactionData{}, "seed", i)

      stamp =
        ValidationStamp.new(tx, %Context{}, "welcome_node_public_key", "coordinator_public_key", [
          "cross_validation_node_public_key"
        ])

      validated_tx = %{tx | validation_stamp: stamp}
      Cache.store_transaction(validated_tx)
    end)

    assert 50 == Enum.count(Cache.list_transactions(0))
    assert 20 == Enum.count(Cache.list_transactions(20))
  end

  test "get_ledger_balance/1 should return the balance of utxo" do
    P2P.add_node(%Node{
      last_public_key: Crypto.node_public_key(),
      first_public_key: Crypto.node_public_key(),
      ip: {127, 0, 0, 1},
      port: 4000,
      ready?: true,
      available?: true
    })

    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    stamp = %ValidationStamp{
      proof_of_work: "",
      proof_of_integrity: "",
      signature: "",
      ledger_operations: %LedgerOperations{
        fee: 0.5,
        node_movements:
          Fee.distribute(
            0.5,
            "welcome_node_public_key",
            "coordinator_public_key",
            ["cross_validator_public_key"],
            ["previous_storage_node_key"]
          ),
        transaction_movements: [
          %TransactionMovement{to: "@Charlie5", amount: 3.0}
        ],
        unspent_outputs: [
          %UnspentOutput{amount: 2.0, from: tx.address},
          %UnspentOutput{amount: 10, from: "@Bob3"}
        ]
      }
    }

    validated_tx = %{tx | validation_stamp: stamp}
    :ok = Cache.store_transaction(validated_tx)

    assert 12.0 == Cache.get_ledger_balance(tx.address)
    assert 3.0 == Cache.get_ledger_balance("@Charlie5")
    assert 0.0475 == Cache.get_ledger_balance(Crypto.hash("coordinator_public_key"))

    tx2 = Transaction.new(:transfer, %TransactionData{}, "seed", 1)

    stamp = %ValidationStamp{
      proof_of_work: "",
      proof_of_integrity: "",
      signature: "",
      ledger_operations: %LedgerOperations{
        fee: 0.5,
        node_movements:
          Fee.distribute(
            0.5,
            "welcome_node_public_key",
            "coordinator_public_key",
            ["cross_validator_public_key"],
            ["previous_storage_node_key"]
          ),
        transaction_movements: [
          %TransactionMovement{to: "@Charlie5", amount: 12}
        ],
        unspent_outputs: []
      }
    }

    validated_tx2 = %{tx2 | validation_stamp: stamp}
    :ok = Cache.store_transaction(validated_tx2)

    assert 0.0 == Cache.get_ledger_balance(tx2.address)
    assert 0.0 == Cache.get_ledger_balance(tx.address)
  end

  test "get_ledger_inputs/1 should retrieve the number of inputs for a given public key" do
    tx = Transaction.new(:node, %TransactionData{}, :crypto.strong_rand_bytes(32), 0)

    stamp = %ValidationStamp{
      proof_of_work: "",
      proof_of_integrity: "",
      signature: "",
      ledger_operations: %LedgerOperations{
        fee: 0.5,
        node_movements:
          Fee.distribute(
            0.5,
            "welcome_node_public_key",
            "coordinator_public_key",
            ["cross_validator_public_key"],
            ["previous_storage_node_key"]
          ),
        transaction_movements: [],
        unspent_outputs: []
      }
    }

    validated_tx = %{tx | validation_stamp: stamp}
    :ok = Cache.store_transaction(validated_tx)

    assert [] == Cache.get_ledger_inputs(tx.address)
    assert 0.0 == Cache.get_ledger_balance(tx.address)

    tx2 = Transaction.new(:transfer, %TransactionData{}, :crypto.strong_rand_bytes(32), 0)

    stamp = %ValidationStamp{
      proof_of_work: "",
      proof_of_integrity: "",
      signature: "",
      ledger_operations: %LedgerOperations{
        fee: 0.5,
        node_movements:
          Fee.distribute(
            0.5,
            "welcome_node_public_key",
            "coordinator_public_key",
            ["cross_validator_public_key"],
            ["previous_storage_node_key"]
          ),
        transaction_movements: [
          %TransactionMovement{to: tx.address, amount: 1.0}
        ],
        unspent_outputs: [
          %UnspentOutput{amount: 2.0, from: tx2.address},
          %UnspentOutput{amount: 10.0, from: "@Bob3"}
        ]
      }
    }

    validated_tx2 = %{tx2 | validation_stamp: stamp}
    :ok = Cache.store_transaction(validated_tx2)

    assert 1.0 == Cache.get_ledger_balance(tx.address)

    assert [
             %TransactionInput{
               from: tx2.address,
               amount: 1.0,
               spent?: false
             }
           ] == Cache.get_ledger_inputs(tx.address)

    assert [
             %TransactionInput{
               from: "@Bob3",
               amount: 10.0,
               spent?: false
             }
           ] == Cache.get_ledger_inputs(tx2.address)
  end
end
