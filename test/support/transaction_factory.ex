defmodule ArchEthic.TransactionFactory do
  @moduledoc false

  alias ArchEthic.Crypto

  alias ArchEthic.Election

  alias ArchEthic.Mining.Fee

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.CrossValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.NodeMovement

  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias ArchEthic.TransactionChain.TransactionData

  def create_valid_transaction(
        %{
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
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())

    tx = Transaction.new(type, %TransactionData{content: content}, seed, index)

    ledger_operations =
      %LedgerOperations{
        fee: Fee.calculate(tx, 0.07),
        transaction_movements: Transaction.get_movements(tx)
      }
      |> LedgerOperations.distribute_rewards(
        coordinator_node,
        [coordinator_node],
        storage_nodes
      )
      |> LedgerOperations.consume_inputs(tx.address, inputs)

    validation_stamp =
      %ValidationStamp{
        timestamp: timestamp,
        proof_of_work: Crypto.first_node_public_key(),
        proof_of_election: Election.validation_nodes_election_seed_sorting(tx, timestamp),
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
          coordinator_node: coordinator_node,
          storage_nodes: storage_nodes
        },
        inputs
      ) do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    ledger_operations =
      %LedgerOperations{
        fee: Fee.calculate(tx, 0.07)
      }
      |> LedgerOperations.distribute_rewards(
        coordinator_node,
        [coordinator_node],
        [coordinator_node] ++ storage_nodes
      )
      |> LedgerOperations.consume_inputs(tx.address, inputs)

    validation_stamp =
      %ValidationStamp{
        timestamp: DateTime.utc_now(),
        proof_of_work: Crypto.first_node_public_key(),
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
          coordinator_node: coordinator_node,
          storage_nodes: storage_nodes
        },
        inputs
      ) do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    ledger_operations =
      %LedgerOperations{
        fee: Fee.calculate(tx, 0.07)
      }
      |> LedgerOperations.distribute_rewards(
        coordinator_node,
        [coordinator_node],
        [coordinator_node] ++ storage_nodes
      )
      |> LedgerOperations.consume_inputs(tx.address, inputs)

    validation_stamp = %ValidationStamp{
      timestamp: DateTime.utc_now(),
      proof_of_work: <<0, 0, :crypto.strong_rand_bytes(32)::binary>>,
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
          coordinator_node: coordinator_node,
          storage_nodes: storage_nodes
        },
        inputs
      ) do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    ledger_operations =
      %LedgerOperations{
        fee: Fee.calculate(tx, 0.07)
      }
      |> LedgerOperations.distribute_rewards(
        coordinator_node,
        [coordinator_node],
        [coordinator_node] ++ storage_nodes
      )
      |> LedgerOperations.consume_inputs(tx.address, inputs)

    validation_stamp = %ValidationStamp{
      timestamp: DateTime.utc_now(),
      proof_of_work: Crypto.first_node_public_key(),
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
          coordinator_node: coordinator_node,
          storage_nodes: storage_nodes
        },
        inputs
      ) do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    ledger_operations =
      %LedgerOperations{
        fee: 1_000_000_000
      }
      |> LedgerOperations.distribute_rewards(
        coordinator_node,
        [coordinator_node],
        [coordinator_node] ++ storage_nodes
      )
      |> LedgerOperations.consume_inputs(tx.address, inputs)

    validation_stamp =
      %ValidationStamp{
        timestamp: DateTime.utc_now(),
        proof_of_work: Crypto.first_node_public_key(),
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
          coordinator_node: coordinator_node,
          storage_nodes: storage_nodes
        },
        inputs
      ) do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    ledger_operations =
      %LedgerOperations{
        fee: Fee.calculate(tx, 0.07),
        transaction_movements: [
          %TransactionMovement{to: "@Bob4", amount: 30_330_000_000, type: :UCO}
        ]
      }
      |> LedgerOperations.distribute_rewards(
        coordinator_node,
        [coordinator_node],
        [coordinator_node] ++ storage_nodes
      )
      |> LedgerOperations.consume_inputs(tx.address, inputs)

    validation_stamp =
      %ValidationStamp{
        timestamp: DateTime.utc_now(),
        proof_of_work: Crypto.first_node_public_key(),
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
        fee: Fee.calculate(tx, 0.07),
        node_movements: [
          %NodeMovement{
            to: Crypto.last_node_public_key(),
            amount: 2_000_000_000,
            roles: [:coordinator_node]
          },
          %NodeMovement{to: "key3", amount: 2_000_000_000, roles: [:cross_validation_node]},
          %NodeMovement{to: "key4", amount: 2_000_000_000, roles: [:previous_storage_node]}
        ]
      }
      |> LedgerOperations.consume_inputs(tx.address, inputs)

    validation_stamp =
      %ValidationStamp{
        timestamp: DateTime.utc_now(),
        proof_of_work: Crypto.first_node_public_key(),
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
