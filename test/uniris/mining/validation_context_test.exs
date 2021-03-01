defmodule Uniris.Mining.ValidationContextTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.Mining.ValidationContext

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.CrossValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionChain.TransactionData

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

    test "should get inconsistency when the node movements are invalid" do
      validation_context = create_context()

      %ValidationContext{
        cross_validation_stamps: [%CrossValidationStamp{inconsistencies: [:node_movements]}]
      } =
        validation_context
        |> ValidationContext.add_validation_stamp(
          create_validation_stamp_with_invalid_node_movements(validation_context)
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
      port: 3000
    }

    coordinator_node = %Node{
      first_public_key: Crypto.node_public_key(),
      last_public_key: Crypto.node_public_key(),
      geo_patch: "AAA",
      ip: {127, 0, 0, 1},
      port: 3000
    }

    cross_validation_nodes = [
      %Node{
        first_public_key: "key2",
        last_public_key: "key2",
        geo_patch: "AAA",
        ip: {127, 0, 0, 1},
        port: 3000
      },
      %Node{
        first_public_key: "key3",
        last_public_key: "key3",
        geo_patch: "AAA",
        ip: {127, 0, 0, 1},
        port: 3000
      }
    ]

    previous_storage_nodes = [
      %Node{
        last_public_key: "key2",
        first_public_key: "key2",
        geo_patch: "AAA",
        available?: true
      },
      %Node{last_public_key: "key3", first_public_key: "key3", geo_patch: "DEA", available?: true}
    ]

    P2P.add_node(welcome_node)
    P2P.add_node(coordinator_node)
    Enum.each(cross_validation_nodes, &P2P.add_node(&1))
    Enum.each(previous_storage_nodes, &P2P.add_node(&1))

    %ValidationContext{
      transaction: Transaction.new(:transfer, %TransactionData{}, "seed", 0),
      previous_storage_nodes: previous_storage_nodes,
      unspent_outputs: [%UnspentOutput{from: "@Alice2", amount: 2.04, type: :UCO}],
      welcome_node: welcome_node,
      coordinator_node: coordinator_node,
      cross_validation_nodes: cross_validation_nodes
    }
  end

  defp create_validation_stamp_with_invalid_signature(%ValidationContext{
         transaction: tx,
         welcome_node: welcome_node,
         coordinator_node: coordinator_node,
         cross_validation_nodes: cross_validation_nodes,
         previous_storage_nodes: previous_storage_nodes,
         unspent_outputs: unspent_outputs
       }) do
    %ValidationStamp{
      proof_of_work: Crypto.node_public_key(0),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      ledger_operations:
        %LedgerOperations{
          fee: Transaction.fee(tx),
          transaction_movements: Transaction.get_movements(tx)
        }
        |> LedgerOperations.from_transaction(tx)
        |> LedgerOperations.consume_inputs(tx.address, unspent_outputs)
        |> LedgerOperations.distribute_rewards(
          welcome_node,
          coordinator_node,
          cross_validation_nodes,
          previous_storage_nodes
        ),
      signature: :crypto.strong_rand_bytes(32)
    }
  end

  defp create_validation_stamp_with_invalid_proof_of_work(%ValidationContext{
         transaction: tx,
         welcome_node: welcome_node,
         coordinator_node: coordinator_node,
         cross_validation_nodes: cross_validation_nodes,
         previous_storage_nodes: previous_storage_nodes,
         unspent_outputs: unspent_outputs
       }) do
    %ValidationStamp{
      proof_of_work: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      ledger_operations:
        %LedgerOperations{
          fee: Transaction.fee(tx),
          transaction_movements: Transaction.get_movements(tx)
        }
        |> LedgerOperations.from_transaction(tx)
        |> LedgerOperations.consume_inputs(tx.address, unspent_outputs)
        |> LedgerOperations.distribute_rewards(
          welcome_node,
          coordinator_node,
          cross_validation_nodes,
          previous_storage_nodes
        )
    }
    |> ValidationStamp.sign()
  end

  defp create_validation_stamp_with_invalid_transaction_fee(%ValidationContext{
         transaction: tx,
         welcome_node: welcome_node,
         coordinator_node: coordinator_node,
         cross_validation_nodes: cross_validation_nodes,
         previous_storage_nodes: previous_storage_nodes,
         unspent_outputs: _unspent_outputs
       }) do
    %ValidationStamp{
      proof_of_work: Crypto.node_public_key(0),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      ledger_operations:
        %LedgerOperations{
          fee: 20.20,
          transaction_movements: Transaction.get_movements(tx),
          unspent_outputs: [
            %UnspentOutput{
              amount: 2.0300000000000002,
              from: tx.address,
              type: :UCO
            }
          ]
        }
        |> LedgerOperations.distribute_rewards(
          welcome_node,
          coordinator_node,
          cross_validation_nodes,
          previous_storage_nodes
        )
    }
    |> ValidationStamp.sign()
  end

  defp create_validation_stamp_with_invalid_transaction_movements(%ValidationContext{
         transaction: tx,
         welcome_node: welcome_node,
         coordinator_node: coordinator_node,
         cross_validation_nodes: cross_validation_nodes,
         previous_storage_nodes: previous_storage_nodes,
         unspent_outputs: _unspent_outputs
       }) do
    %ValidationStamp{
      proof_of_work: Crypto.node_public_key(0),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      ledger_operations:
        %LedgerOperations{
          fee: Transaction.fee(tx),
          transaction_movements: [
            %TransactionMovement{to: "@Bob3", amount: 2000, type: :UCO}
          ],
          unspent_outputs: [
            %UnspentOutput{
              amount: 2.0300000000000002,
              from: tx.address,
              type: :UCO
            }
          ]
        }
        |> LedgerOperations.distribute_rewards(
          welcome_node,
          coordinator_node,
          cross_validation_nodes,
          previous_storage_nodes
        )
    }
    |> ValidationStamp.sign()
  end

  defp create_validation_stamp_with_invalid_unspent_outputs(%ValidationContext{
         transaction: tx,
         welcome_node: welcome_node,
         coordinator_node: coordinator_node,
         cross_validation_nodes: cross_validation_nodes,
         previous_storage_nodes: previous_storage_nodes,
         unspent_outputs: _unspent_outputs
       }) do
    %ValidationStamp{
      proof_of_work: Crypto.node_public_key(0),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      ledger_operations:
        %LedgerOperations{
          fee: Transaction.fee(tx),
          transaction_movements: Transaction.get_movements(tx),
          unspent_outputs: [
            %UnspentOutput{
              amount: 1000,
              from: tx.address,
              type: :UCO
            }
          ]
        }
        |> LedgerOperations.distribute_rewards(
          welcome_node,
          coordinator_node,
          cross_validation_nodes,
          previous_storage_nodes
        )
    }
    |> ValidationStamp.sign()
  end

  defp create_validation_stamp_with_invalid_node_movements(%ValidationContext{
         transaction: tx,
         welcome_node: welcome_node,
         coordinator_node: coordinator_node,
         cross_validation_nodes: cross_validation_nodes,
         previous_storage_nodes: previous_storage_nodes,
         unspent_outputs: _unspent_outputs
       }) do
    %ValidationStamp{
      proof_of_work: Crypto.node_public_key(0),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      ledger_operations: %LedgerOperations{
        fee: Transaction.fee(tx),
        transaction_movements: Transaction.get_movements(tx),
        unspent_outputs: [
          %UnspentOutput{
            amount: 2.0300000000000002,
            from: tx.address,
            type: :UCO
          }
        ],
        node_movements: [
          %NodeMovement{to: welcome_node.last_public_key, amount: 10.0, roles: [:welcome_node]},
          %NodeMovement{
            to: coordinator_node.last_public_key,
            amount: 20.0,
            roles: [:coordinator_node]
          },
          %NodeMovement{
            to: Enum.at(cross_validation_nodes, 0).last_public_key,
            amount: 15.0,
            roles: [:cross_validation_node]
          },
          %NodeMovement{
            to: Enum.at(cross_validation_nodes, 1).last_public_key,
            amount: 15.0,
            roles: [:cross_validation_node]
          },
          %NodeMovement{
            to: Enum.at(previous_storage_nodes, 0).last_public_key,
            amount: 10.0,
            roles: [:previous_storage_node]
          },
          %NodeMovement{
            to: Enum.at(previous_storage_nodes, 1).last_public_key,
            amount: 10.0,
            roles: [:previous_storage_node]
          }
        ]
      }
    }
    |> ValidationStamp.sign()
  end

  defp create_validation_stamp_with_invalid_errors(%ValidationContext{
         transaction: tx,
         welcome_node: welcome_node,
         coordinator_node: coordinator_node,
         cross_validation_nodes: cross_validation_nodes,
         previous_storage_nodes: previous_storage_nodes,
         unspent_outputs: unspent_outputs
       }) do
    %ValidationStamp{
      proof_of_work: Crypto.node_public_key(0),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      ledger_operations:
        %LedgerOperations{
          fee: Transaction.fee(tx),
          transaction_movements: Transaction.get_movements(tx)
        }
        |> LedgerOperations.consume_inputs(tx.address, unspent_outputs)
        |> LedgerOperations.distribute_rewards(
          welcome_node,
          coordinator_node,
          cross_validation_nodes,
          previous_storage_nodes
        ),
      errors: [:contract_validation]
    }
    |> ValidationStamp.sign()
  end
end
