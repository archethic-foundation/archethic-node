defmodule Archethic.Mining.ValidationContextTest do
  use ArchethicCase

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.Mining.Fee
  alias Archethic.Mining.ValidationContext

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionData

  doctest ValidationContext

  describe "cross_validate/1" do
    test "should get inconsistency when the validation stamp signature is invalid" do
      validation_context = create_context()

      %ValidationContext{
        cross_validation_stamps: [%CrossValidationStamp{inconsistencies: [:signature]}]
      } =
        validation_context
        |> ValidationContext.add_validation_stamp(
          create_validation_stamp_with_invalid_signature(validation_context)
        )
        |> ValidationContext.cross_validate()
    end

    test "should get inconsistency when the proof of work is invalid" do
      validation_context = create_context()

      %ValidationContext{
        cross_validation_stamps: [%CrossValidationStamp{inconsistencies: [:proof_of_work]}]
      } =
        validation_context
        |> ValidationContext.add_validation_stamp(
          create_validation_stamp_with_invalid_proof_of_work(validation_context)
        )
        |> ValidationContext.cross_validate()
    end

    test "should get inconsistency when the transaction fee is invalid" do
      validation_context = create_context()

      %ValidationContext{
        cross_validation_stamps: [%CrossValidationStamp{inconsistencies: [:transaction_fee]}]
      } =
        validation_context
        |> ValidationContext.add_validation_stamp(
          create_validation_stamp_with_invalid_transaction_fee(validation_context)
        )
        |> ValidationContext.cross_validate()
    end

    test "should get inconsistency when the transaction movements are invalid" do
      validation_context = create_context()

      %ValidationContext{
        cross_validation_stamps: [
          %CrossValidationStamp{inconsistencies: [:transaction_movements]}
        ]
      } =
        validation_context
        |> ValidationContext.add_validation_stamp(
          create_validation_stamp_with_invalid_transaction_movements(validation_context)
        )
        |> ValidationContext.cross_validate()
    end

    test "should get inconsistency when the unspent outputs are invalid" do
      validation_context = create_context()

      %ValidationContext{
        cross_validation_stamps: [%CrossValidationStamp{inconsistencies: [:unspent_outputs]}]
      } =
        validation_context
        |> ValidationContext.add_validation_stamp(
          create_validation_stamp_with_invalid_unspent_outputs(validation_context)
        )
        |> ValidationContext.cross_validate()
    end

    test "should get inconsistency when the errors are invalid" do
      validation_context = create_context()

      %ValidationContext{
        cross_validation_stamps: [%CrossValidationStamp{inconsistencies: [:errors]}]
      } =
        validation_context
        |> ValidationContext.add_validation_stamp(
          create_validation_stamp_with_invalid_errors(validation_context)
        )
        |> ValidationContext.cross_validate()
    end
  end

  defp create_context do
    welcome_node = %Node{
      last_public_key: "key1",
      first_public_key: "key1",
      geo_patch: "AAA",
      ip: {127, 0, 0, 1},
      port: 3000,
      reward_address: :crypto.strong_rand_bytes(32),
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-2)
    }

    coordinator_node = %Node{
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      geo_patch: "AAA",
      ip: {127, 0, 0, 1},
      port: 3000,
      reward_address: :crypto.strong_rand_bytes(32),
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-2)
    }

    cross_validation_nodes = [
      %Node{
        first_public_key: "key2",
        last_public_key: "key2",
        geo_patch: "AAA",
        ip: {127, 0, 0, 1},
        port: 3000,
        reward_address: :crypto.strong_rand_bytes(32),
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-2)
      },
      %Node{
        first_public_key: "key3",
        last_public_key: "key3",
        geo_patch: "AAA",
        ip: {127, 0, 0, 1},
        port: 3000,
        reward_address: :crypto.strong_rand_bytes(32),
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-2)
      }
    ]

    previous_storage_nodes = [
      %Node{
        last_public_key: "key2",
        first_public_key: "key2",
        geo_patch: "AAA",
        available?: true,
        reward_address: :crypto.strong_rand_bytes(32),
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-2)
      },
      %Node{
        last_public_key: "key3",
        first_public_key: "key3",
        geo_patch: "DEA",
        available?: true,
        reward_address: :crypto.strong_rand_bytes(32),
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-2)
      }
    ]

    P2P.add_and_connect_node(welcome_node)
    P2P.add_and_connect_node(coordinator_node)
    Enum.each(cross_validation_nodes, &P2P.add_and_connect_node(&1))
    Enum.each(previous_storage_nodes, &P2P.add_and_connect_node(&1))

    %ValidationContext{
      transaction: Transaction.new(:transfer, %TransactionData{}, "seed", 0),
      previous_storage_nodes: previous_storage_nodes,
      unspent_outputs: [%UnspentOutput{from: "@Alice2", amount: 204_000_000, type: :UCO}],
      welcome_node: welcome_node,
      coordinator_node: coordinator_node,
      cross_validation_nodes: cross_validation_nodes,
      valid_pending_transaction?: true
    }
  end

  defp create_validation_stamp_with_invalid_signature(%ValidationContext{
         transaction: tx,
         unspent_outputs: unspent_outputs
       }) do
    %ValidationStamp{
      timestamp: DateTime.utc_now(),
      proof_of_work: Crypto.origin_node_public_key(),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations:
        %LedgerOperations{
          fee: Fee.calculate(tx, 0.07),
          transaction_movements: Transaction.get_movements(tx)
        }
        |> LedgerOperations.from_transaction(tx)
        |> LedgerOperations.consume_inputs(tx.address, unspent_outputs),
      signature: :crypto.strong_rand_bytes(32)
    }
  end

  defp create_validation_stamp_with_invalid_proof_of_work(%ValidationContext{
         transaction: tx,
         unspent_outputs: unspent_outputs
       }) do
    %ValidationStamp{
      timestamp: DateTime.utc_now(),
      proof_of_work: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations:
        %LedgerOperations{
          fee: Fee.calculate(tx, 0.07),
          transaction_movements: Transaction.get_movements(tx)
        }
        |> LedgerOperations.from_transaction(tx)
        |> LedgerOperations.consume_inputs(tx.address, unspent_outputs)
    }
    |> ValidationStamp.sign()
  end

  defp create_validation_stamp_with_invalid_transaction_fee(%ValidationContext{
         transaction: tx,
         unspent_outputs: unspent_outputs
       }) do
    %ValidationStamp{
      timestamp: DateTime.utc_now(),
      proof_of_work: Crypto.origin_node_public_key(),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations:
        %LedgerOperations{
          fee: 2_020_000_000,
          transaction_movements: Transaction.get_movements(tx)
        }
        |> LedgerOperations.consume_inputs(tx.address, unspent_outputs)
    }
    |> ValidationStamp.sign()
  end

  defp create_validation_stamp_with_invalid_transaction_movements(%ValidationContext{
         transaction: tx,
         unspent_outputs: unspent_outputs
       }) do
    fee = Fee.calculate(tx, 0.07)

    %ValidationStamp{
      timestamp: DateTime.utc_now(),
      proof_of_work: Crypto.origin_node_public_key(),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations:
        %LedgerOperations{
          fee: fee,
          transaction_movements: [
            %TransactionMovement{to: "@Bob3", amount: 200_000_000_000, type: :UCO}
          ],
          unspent_outputs: [
            %UnspentOutput{
              amount: Enum.reduce(unspent_outputs, 0, &(&1.amount + &2)) - fee,
              from: tx.address,
              type: :UCO
            }
          ]
        }
        |> LedgerOperations.consume_inputs(tx.address, unspent_outputs)
    }
    |> ValidationStamp.sign()
  end

  defp create_validation_stamp_with_invalid_unspent_outputs(%ValidationContext{
         transaction: tx,
         unspent_outputs: _unspent_outputs
       }) do
    %ValidationStamp{
      timestamp: DateTime.utc_now(),
      proof_of_work: Crypto.origin_node_public_key(),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations: %LedgerOperations{
        fee: Fee.calculate(tx, 0.07),
        transaction_movements: Transaction.get_movements(tx),
        unspent_outputs: [
          %UnspentOutput{
            amount: 100_000_000_000,
            from: tx.address,
            type: :UCO
          }
        ]
      }
    }
    |> ValidationStamp.sign()
  end

  defp create_validation_stamp_with_invalid_errors(%ValidationContext{
         transaction: tx,
         unspent_outputs: unspent_outputs
       }) do
    %ValidationStamp{
      timestamp: DateTime.utc_now(),
      proof_of_work: Crypto.origin_node_public_key(),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations:
        %LedgerOperations{
          fee: Fee.calculate(tx, 0.07),
          transaction_movements: Transaction.get_movements(tx)
        }
        |> LedgerOperations.consume_inputs(tx.address, unspent_outputs),
      errors: [:contract_validation]
    }
    |> ValidationStamp.sign()
  end
end
