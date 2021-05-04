defmodule Uniris.Replication.TransactionValidatorTest do
  use UnirisCase, async: false

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.Replication.TransactionValidator

  alias Uniris.SharedSecrets
  alias Uniris.SharedSecrets.MemTables.NetworkLookup

  alias Uniris.TransactionFactory

  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  setup do
    SharedSecrets.add_origin_public_key(:software, Crypto.node_public_key(0))

    Crypto.generate_deterministic_keypair("daily_nonce_seed")
    |> elem(0)
    |> NetworkLookup.set_daily_nonce_public_key(DateTime.utc_now())

    welcome_node = %Node{
      first_public_key: "key1",
      last_public_key: "key1",
      available?: true,
      geo_patch: "BBB"
    }

    coordinator_node = %Node{
      first_public_key: Crypto.node_public_key(0),
      last_public_key: Crypto.node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-1),
      geo_patch: "AAA"
    }

    storage_nodes = [
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key3",
        last_public_key: "key3",
        available?: true,
        geo_patch: "BBB",
        authorization_date: DateTime.utc_now() |> DateTime.add(-1),
        authorized?: true
      }
    ]

    Enum.each(storage_nodes, &P2P.add_node(&1))

    P2P.add_node(welcome_node)
    P2P.add_node(coordinator_node)

    {:ok,
     %{
       welcome_node: welcome_node,
       coordinator_node: coordinator_node,
       storage_nodes: storage_nodes
     }}
  end

  describe "validate/2" do
    test "should return {:error, :invalid_atomic_commitment} when the atomic commitment is not reached",
         context do
      unspent_outputs = [%UnspentOutput{from: "@Alice2", amount: 10.0, type: :UCO}]

      assert {:error, :invalid_atomic_commitment} =
               context
               |> TransactionFactory.create_transaction_with_not_atomic_commitment(
                 unspent_outputs
               )
               |> TransactionValidator.validate()
    end

    test "should return {:error, :invalid_proof_of_work} when an invalid proof of work",
         context do
      assert {:error, :invalid_proof_of_work} =
               context
               |> TransactionFactory.create_transaction_with_invalid_proof_of_work([])
               |> TransactionValidator.validate()
    end

    test "should return {:error, :invalid_validation_stamp_signature} when the validation stamp signature is invalid",
         context do
      assert {:error, :invalid_validation_stamp_signature} =
               context
               |> TransactionFactory.create_transaction_with_invalid_validation_stamp_signature(
                 []
               )
               |> TransactionValidator.validate()
    end

    test "should return {:error, :invalid_transaction_fee} when the fees are invalid",
         context do
      assert {:error, :invalid_transaction_fee} =
               context
               |> TransactionFactory.create_transaction_with_invalid_fee([])
               |> TransactionValidator.validate()
    end

    test "should return {:error, :invalid_transaction_movements} when the transaction movements are invalid",
         context do
      assert {:error, :invalid_transaction_movements} =
               context
               |> TransactionFactory.create_transaction_with_invalid_transaction_movements([])
               |> TransactionValidator.validate()
    end

    test "should return {:error, ::invalid_cross_validation_nodes_movements} when the node movements are invalid",
         context do
      unspent_outputs = [%UnspentOutput{from: "@Alice2", amount: 10.0, type: :UCO}]

      assert {:error, :invalid_cross_validation_nodes_movements} =
               context
               |> TransactionFactory.create_transaction_with_invalid_node_movements(
                 unspent_outputs
               )
               |> TransactionValidator.validate()
    end

    test "should return {:error, :invalid_transaction_with_inconsistencies} when there is an atomic commitment but with inconsistencies",
         context do
      unspent_outputs = [%UnspentOutput{from: "@Alice2", amount: 10.0, type: :UCO}]

      assert {:error, :invalid_transaction_with_inconsistencies} =
               context
               |> TransactionFactory.create_valid_transaction_with_inconsistencies(
                 unspent_outputs
               )
               |> TransactionValidator.validate()
    end

    test "should return :ok when the transaction is valid", context do
      unspent_outputs = [%UnspentOutput{from: "@Alice2", amount: 10.0, type: :UCO}]

      assert :ok =
               context
               |> TransactionFactory.create_valid_transaction(unspent_outputs)
               |> TransactionValidator.validate()
    end
  end

  describe "validate/3" do
    test "should return :ok when the transaction is valid", context do
      unspent_outputs = [%UnspentOutput{from: "@Alice2", amount: 10.0, type: :UCO}]

      assert :ok =
               context
               |> TransactionFactory.create_valid_transaction(unspent_outputs)
               |> TransactionValidator.validate(nil, unspent_outputs)
    end
  end
end
