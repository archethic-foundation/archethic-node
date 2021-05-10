defmodule Uniris.TransactionFactory do
  @moduledoc false

  alias Uniris.Crypto

  alias Uniris.Election

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.CrossValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Uniris.TransactionChain.TransactionData

  def create_valid_transaction(
        %{
          welcome_node: welcome_node,
          coordinator_node: coordinator_node,
          storage_nodes: storage_nodes
        },
        inputs \\ [],
        opts \\ []
      ) do
    type = Keyword.get(opts, :type, :transfer)
    seed = Keyword.get(opts, :seed, "seed")
    index = Keyword.get(opts, :index, 0)
    content = Keyword.get(opts, :content, "")

    tx = Transaction.new(type, %TransactionData{content: content}, seed, index)

    ledger_operations =
      %LedgerOperations{
        fee: Transaction.fee(tx),
        transaction_movements: Transaction.get_movements(tx)
      }
      |> LedgerOperations.distribute_rewards(
        welcome_node,
        coordinator_node,
        [coordinator_node],
        storage_nodes
      )
      |> LedgerOperations.consume_inputs(tx.address, inputs)

    validation_stamp =
      %ValidationStamp{
        timestamp: DateTime.utc_now(),
        proof_of_work: Crypto.node_public_key(0),
        proof_of_election:
          Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
        proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
        ledger_operations: ledger_operations
      }
      |> ValidationStamp.sign()

    cross_validation_stamp = CrossValidationStamp.sign(%CrossValidationStamp{}, validation_stamp)

    %{tx | validation_stamp: validation_stamp, cross_validation_stamps: [cross_validation_stamp]}
  end

  def create_transaction_with_not_atomic_commitment(context, unspent_outputs) do
    tx = create_valid_transaction(context, unspent_outputs)

    cross_validation_stamp =
      CrossValidationStamp.sign(
        %CrossValidationStamp{inconsistencies: [:proof_of_work]},
        tx.validation_stamp
      )

    Map.update!(tx, :cross_validation_stamps, &[cross_validation_stamp | &1])
  end

  def create_valid_transaction_with_inconsistencies(
        %{
          welcome_node: welcome_node,
          coordinator_node: coordinator_node,
          storage_nodes: storage_nodes
        },
        inputs
      ) do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    ledger_operations =
      %LedgerOperations{
        # TODO: change when the fee algorithm will be implemented
        fee: 0.01
      }
      |> LedgerOperations.distribute_rewards(
        welcome_node,
        coordinator_node,
        [coordinator_node],
        [welcome_node, coordinator_node] ++ storage_nodes
      )
      |> LedgerOperations.consume_inputs(tx.address, inputs)

    validation_stamp =
      %ValidationStamp{
        timestamp: DateTime.utc_now(),
        proof_of_work: Crypto.node_public_key(0),
        proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
        proof_of_election:
          Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
        ledger_operations: ledger_operations
      }
      |> ValidationStamp.sign()

    cross_validation_stamp =
      CrossValidationStamp.sign(
        %CrossValidationStamp{inconsistencies: [:signature]},
        validation_stamp
      )

    %{tx | validation_stamp: validation_stamp, cross_validation_stamps: [cross_validation_stamp]}
  end

  def create_transaction_with_invalid_proof_of_work(
        %{
          welcome_node: welcome_node,
          coordinator_node: coordinator_node,
          storage_nodes: storage_nodes
        },
        inputs
      ) do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    ledger_operations =
      %LedgerOperations{
        # TODO: change when the fee algorithm will be implemented
        fee: 0.01
      }
      |> LedgerOperations.distribute_rewards(
        welcome_node,
        coordinator_node,
        [coordinator_node],
        [welcome_node, coordinator_node] ++ storage_nodes
      )
      |> LedgerOperations.consume_inputs(tx.address, inputs)

    validation_stamp = %ValidationStamp{
      timestamp: DateTime.utc_now(),
      proof_of_work: <<0, :crypto.strong_rand_bytes(32)::binary>>,
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations: ledger_operations,
      signature: :crypto.strong_rand_bytes(32)
    }

    cross_validation_stamp =
      CrossValidationStamp.sign(
        %CrossValidationStamp{},
        validation_stamp
      )

    %{tx | validation_stamp: validation_stamp, cross_validation_stamps: [cross_validation_stamp]}
  end

  def create_transaction_with_invalid_validation_stamp_signature(
        %{
          welcome_node: welcome_node,
          coordinator_node: coordinator_node,
          storage_nodes: storage_nodes
        },
        inputs
      ) do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    ledger_operations =
      %LedgerOperations{
        # TODO: change when the fee algorithm will be implemented
        fee: 0.01
      }
      |> LedgerOperations.distribute_rewards(
        welcome_node,
        coordinator_node,
        [coordinator_node],
        [welcome_node, coordinator_node] ++ storage_nodes
      )
      |> LedgerOperations.consume_inputs(tx.address, inputs)

    validation_stamp = %ValidationStamp{
      timestamp: DateTime.utc_now(),
      proof_of_work: Crypto.node_public_key(0),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations: ledger_operations,
      signature: :crypto.strong_rand_bytes(32)
    }

    cross_validation_stamp =
      CrossValidationStamp.sign(
        %CrossValidationStamp{},
        validation_stamp
      )

    %{tx | validation_stamp: validation_stamp, cross_validation_stamps: [cross_validation_stamp]}
  end

  def create_transaction_with_invalid_fee(
        %{
          welcome_node: welcome_node,
          coordinator_node: coordinator_node,
          storage_nodes: storage_nodes
        },
        inputs
      ) do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    ledger_operations =
      %LedgerOperations{
        fee: 10
      }
      |> LedgerOperations.distribute_rewards(
        welcome_node,
        coordinator_node,
        [coordinator_node],
        [welcome_node, coordinator_node] ++ storage_nodes
      )
      |> LedgerOperations.consume_inputs(tx.address, inputs)

    validation_stamp =
      %ValidationStamp{
        timestamp: DateTime.utc_now(),
        proof_of_work: Crypto.node_public_key(0),
        proof_of_election:
          Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
        proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
        ledger_operations: ledger_operations
      }
      |> ValidationStamp.sign()

    cross_validation_stamp =
      CrossValidationStamp.sign(
        %CrossValidationStamp{},
        validation_stamp
      )

    %{tx | validation_stamp: validation_stamp, cross_validation_stamps: [cross_validation_stamp]}
  end

  def create_transaction_with_invalid_transaction_movements(
        %{
          welcome_node: welcome_node,
          coordinator_node: coordinator_node,
          storage_nodes: storage_nodes
        },
        inputs
      ) do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    ledger_operations =
      %LedgerOperations{
        fee: 0.01,
        transaction_movements: [%TransactionMovement{to: "@Bob4", amount: 303.30, type: :UCO}]
      }
      |> LedgerOperations.distribute_rewards(
        welcome_node,
        coordinator_node,
        [coordinator_node],
        [welcome_node, coordinator_node] ++ storage_nodes
      )
      |> LedgerOperations.consume_inputs(tx.address, inputs)

    validation_stamp =
      %ValidationStamp{
        timestamp: DateTime.utc_now(),
        proof_of_work: Crypto.node_public_key(0),
        proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
        proof_of_election:
          Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
        ledger_operations: ledger_operations
      }
      |> ValidationStamp.sign()

    cross_validation_stamp =
      CrossValidationStamp.sign(
        %CrossValidationStamp{},
        validation_stamp
      )

    %{tx | validation_stamp: validation_stamp, cross_validation_stamps: [cross_validation_stamp]}
  end

  def create_transaction_with_invalid_node_movements(_context, inputs) do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    ledger_operations =
      %LedgerOperations{
        fee: 0.01,
        node_movements: [
          %NodeMovement{to: "key1", amount: 20, roles: [:welcome_node]},
          %NodeMovement{to: Crypto.node_public_key(), amount: 20, roles: [:coordinator_node]},
          %NodeMovement{to: "key3", amount: 20, roles: [:cross_validation_node]},
          %NodeMovement{to: "key4", amount: 20, roles: [:previous_storage_node]}
        ]
      }
      |> LedgerOperations.consume_inputs(tx.address, inputs)

    validation_stamp =
      %ValidationStamp{
        timestamp: DateTime.utc_now(),
        proof_of_work: Crypto.node_public_key(0),
        proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
        proof_of_election:
          Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
        ledger_operations: ledger_operations
      }
      |> ValidationStamp.sign()

    cross_validation_stamp =
      CrossValidationStamp.sign(
        %CrossValidationStamp{},
        validation_stamp
      )

    %{tx | validation_stamp: validation_stamp, cross_validation_stamps: [cross_validation_stamp]}
  end
end
