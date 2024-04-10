defmodule Archethic.Mining.ValidationContextTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.Mining.Fee
  alias Archethic.Mining.ValidationContext

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.SharedSecrets

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.Recipient

  alias Archethic.TransactionFactory

  import Mock

  doctest ValidationContext

  describe "aggregate_mining_context/7" do
    test "should do the intersection of utxos" do
      now = DateTime.utc_now() |> DateTime.truncate(:millisecond)

      utxos_coordinator =
        [
          %UnspentOutput{
            from: "@Alice1",
            amount: 1,
            type: :UCO,
            timestamp: now
          },
          %UnspentOutput{
            from: "@Alice2",
            amount: 2,
            type: :UCO,
            timestamp: now
          }
        ]
        |> VersionedUnspentOutput.wrap_unspent_outputs(current_protocol_version())

      utxos_validator =
        [
          %UnspentOutput{
            from: "@Alice1",
            amount: 1,
            type: :UCO,
            timestamp: now
          },
          %UnspentOutput{
            from: "@Alice2",
            amount: 2,
            type: :UCO,
            timestamp: now
          },

          # this utxo does not intersect so it'll ignored
          %UnspentOutput{
            from: "@Alice3",
            amount: 3,
            type: :UCO,
            timestamp: now
          }
        ]
        |> VersionedUnspentOutput.wrap_unspent_outputs(current_protocol_version())

      assert %ValidationContext{
               previous_storage_nodes: [
                 %Node{first_public_key: "key1"},
                 %Node{first_public_key: "key2"}
               ],
               chain_storage_nodes_view: <<1::1, 1::1, 1::1>>,
               beacon_storage_nodes_view: <<1::1, 1::1, 1::1>>,
               io_storage_nodes_view: <<1::1, 0::1, 0::1>>,
               cross_validation_nodes_confirmation: <<0::1, 1::1>>,
               cross_validation_nodes: [
                 %Node{last_public_key: "key3"},
                 %Node{last_public_key: "key5"}
               ],
               unspent_outputs: ^utxos_coordinator
             } =
               %ValidationContext{
                 previous_storage_nodes: [%Node{first_public_key: "key1"}],
                 chain_storage_nodes_view: <<1::1, 1::1, 1::1>>,
                 beacon_storage_nodes_view: <<1::1, 0::1, 1::1>>,
                 io_storage_nodes_view: <<1::1, 0::1, 0::1>>,
                 cross_validation_nodes: [
                   %Node{last_public_key: "key3"},
                   %Node{last_public_key: "key5"}
                 ],
                 cross_validation_nodes_confirmation: <<0::1, 0::1>>,
                 unspent_outputs: utxos_coordinator
               }
               |> ValidationContext.aggregate_mining_context(
                 [%Node{first_public_key: "key2"}],
                 <<1::1, 0::1, 1::1>>,
                 <<1::1, 1::1, 1::1>>,
                 <<1::1, 0::1, 0::1>>,
                 "key5",
                 Enum.map(utxos_validator, &VersionedUnspentOutput.hash/1)
               )
    end
  end

  describe "create_validation_stamp/1" do
    test "should return the correct movements even if there are multiple to the same address" do
      timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)
      transfer_address = random_address()
      resolved_address = random_address()

      validation_context = %ValidationContext{
        create_context(timestamp)
        | transaction:
            Transaction.new(
              :transfer,
              %TransactionData{
                ledger: %Ledger{
                  uco: %UCOLedger{
                    transfers: [
                      %UCOLedger.Transfer{to: transfer_address, amount: 10},
                      %UCOLedger.Transfer{to: transfer_address, amount: 20},
                      %UCOLedger.Transfer{to: transfer_address, amount: 30}
                    ]
                  }
                }
              },
              "seed",
              0
            ),
          resolved_addresses: %{transfer_address => resolved_address}
      }

      expected_movements = [%TransactionMovement{to: resolved_address, amount: 60, type: :UCO}]

      assert %ValidationContext{
               validation_stamp: %ValidationStamp{
                 ledger_operations: %LedgerOperations{transaction_movements: ^expected_movements}
               }
             } = ValidationContext.create_validation_stamp(validation_context)
    end
  end

  describe "cross_validate/1" do
    test "should validate with a valid validation stamp" do
      timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)
      validation_context = create_context(timestamp)

      SharedSecrets.add_origin_public_key(:software, Crypto.origin_node_public_key())

      %ValidationContext{
        cross_validation_stamps: [%CrossValidationStamp{inconsistencies: []}]
      } =
        validation_context
        |> ValidationContext.add_validation_stamp(create_validation_stamp(validation_context))
        |> ValidationContext.cross_validate()
    end

    test "should validate even if validation_time and cross_validation_time are in different oracle bucket" do
      validation_context = create_context(~U[2023-12-11 09:00:01Z])

      validation_context2 = %ValidationContext{
        validation_context
        | validation_time: ~U[2023-12-11 08:59:59Z]
      }

      SharedSecrets.add_origin_public_key(:software, Crypto.origin_node_public_key())

      # the cross valiadation (09:00:01) should look for the price a 08:00:00
      # because it MUST look at the price of validation_stamp.timestamp (08:59:59)
      with_mock(Archethic.OracleChain, [:passthrough],
        get_uco_price: fn ~U[2023-12-11 08:00:00Z] ->
          [eur: 0.05, usd: 0.07]
        end
      ) do
        assert %ValidationContext{
                 cross_validation_stamps: [%CrossValidationStamp{inconsistencies: []}]
               } =
                 validation_context
                 |> ValidationContext.add_validation_stamp(
                   create_validation_stamp(validation_context2)
                 )
                 |> ValidationContext.cross_validate()
      end
    end

    test "should get inconsistency when the user has not enough funds" do
      validation_context =
        %ValidationContext{create_context() | aggregated_utxos: []}
        |> ValidationContext.create_validation_stamp()

      assert validation_context.validation_stamp.error == :insufficient_funds
    end

    test "should get error when the recipients are not distinct/unique" do
      contract_address1 = random_address()
      contract_address2 = random_address()
      latest_contract_address = random_address()

      validation_context =
        %ValidationContext{
          create_context()
          | resolved_addresses: %{
              contract_address1 => latest_contract_address,
              contract_address2 => latest_contract_address
            },
            transaction:
              Transaction.new(
                :transfer,
                %TransactionData{
                  recipients: [
                    %Recipient{address: contract_address1},
                    %Recipient{address: contract_address2}
                  ]
                },
                "seed",
                0
              )
        }
        |> ValidationContext.create_validation_stamp()

      assert validation_context.validation_stamp.error == :recipients_not_distinct
    end

    test "should get inconsistency when the validation stamp signature is invalid" do
      validation_context = create_context()

      SharedSecrets.add_origin_public_key(:software, Crypto.origin_node_public_key())

      assert %ValidationContext{
               cross_validation_stamps: [%CrossValidationStamp{inconsistencies: [:signature]}]
             } =
               validation_context
               |> ValidationContext.add_validation_stamp(
                 create_validation_stamp_with_invalid_signature(validation_context)
               )
               |> ValidationContext.cross_validate()
    end

    test "should get inconsistency when the proof of work is invalid" do
      timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)
      validation_context = create_context(timestamp)

      SharedSecrets.add_origin_public_key(:software, Crypto.origin_node_public_key())

      assert %ValidationContext{
               cross_validation_stamps: [%CrossValidationStamp{inconsistencies: [:proof_of_work]}]
             } =
               validation_context
               |> ValidationContext.add_validation_stamp(
                 create_validation_stamp_with_invalid_proof_of_work(validation_context)
               )
               |> ValidationContext.cross_validate()
    end

    test "should get inconsistency when the proof of work is not in authorized keys" do
      timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)
      validation_context = create_context(timestamp)

      assert %ValidationContext{
               cross_validation_stamps: [%CrossValidationStamp{inconsistencies: [:proof_of_work]}]
             } =
               validation_context
               |> ValidationContext.add_validation_stamp(
                 create_validation_stamp(validation_context)
               )
               |> ValidationContext.cross_validate()
    end

    test "should get inconsistency when the transaction fee is invalid" do
      validation_context = create_context()
      SharedSecrets.add_origin_public_key(:software, Crypto.origin_node_public_key())

      assert %ValidationContext{
               cross_validation_stamps: [
                 %CrossValidationStamp{inconsistencies: [:transaction_fee]}
               ]
             } =
               validation_context
               |> ValidationContext.add_validation_stamp(
                 create_validation_stamp_with_invalid_transaction_fee(validation_context)
               )
               |> ValidationContext.cross_validate()
    end

    test "should get inconsistency when the transaction movements are invalid" do
      timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)
      validation_context = create_context(timestamp)

      SharedSecrets.add_origin_public_key(:software, Crypto.origin_node_public_key())

      assert %ValidationContext{
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

      SharedSecrets.add_origin_public_key(:software, Crypto.origin_node_public_key())

      assert %ValidationContext{
               cross_validation_stamps: [
                 %CrossValidationStamp{inconsistencies: [:unspent_outputs]}
               ]
             } =
               validation_context
               |> ValidationContext.add_validation_stamp(
                 create_validation_stamp_with_invalid_unspent_outputs(validation_context)
               )
               |> ValidationContext.cross_validate()
    end

    test "should get inconsistency when the consumed inputs are invalid" do
      validation_context = create_context()

      SharedSecrets.add_origin_public_key(:software, Crypto.origin_node_public_key())

      assert %ValidationContext{
               cross_validation_stamps: [
                 %CrossValidationStamp{inconsistencies: [:consumed_inputs]}
               ]
             } =
               validation_context
               |> ValidationContext.add_validation_stamp(
                 create_validation_stamp_with_invalid_consumed_inputs(validation_context)
               )
               |> ValidationContext.cross_validate()
    end

    test "should get inconsistency when the errors are invalid" do
      validation_context = create_context()

      SharedSecrets.add_origin_public_key(:software, Crypto.origin_node_public_key())

      assert %ValidationContext{
               cross_validation_stamps: [%CrossValidationStamp{inconsistencies: [:error]}]
             } =
               validation_context
               |> ValidationContext.add_validation_stamp(
                 create_validation_stamp_with_invalid_errors(validation_context)
               )
               |> ValidationContext.cross_validate()
    end
  end

  describe "get_confirmed_replication_nodes/1" do
    test "should return the correct nodes" do
      ctx = create_context()
      chain_storage_nodes = [ctx.welcome_node, ctx.coordinator_node]

      node1_ctx = %ValidationContext{
        ctx
        | chain_storage_nodes: chain_storage_nodes
      }

      storage_nodes_confirmations =
        chain_storage_nodes
        |> Enum.map(&ValidationContext.get_chain_storage_position(node1_ctx, &1.first_public_key))
        |> Enum.map(fn {:ok, idx} -> {idx, :fake_confirmation} end)

      node2_ctx = %ValidationContext{
        ctx
        | storage_nodes_confirmations: storage_nodes_confirmations
      }

      assert ^chain_storage_nodes = ValidationContext.get_confirmed_replication_nodes(node2_ctx)
    end
  end

  defp create_context(validation_time \\ DateTime.utc_now() |> DateTime.truncate(:millisecond)) do
    welcome_node = %Node{
      last_public_key: "key1",
      first_public_key: "key1",
      geo_patch: "AAA",
      ip: {127, 0, 0, 1},
      port: 3000,
      reward_address: :crypto.strong_rand_bytes(32),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-2)
    }

    coordinator_node = %Node{
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      geo_patch: "AAA",
      ip: {127, 0, 0, 1},
      port: 3001,
      reward_address: :crypto.strong_rand_bytes(32),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-2)
    }

    previous_storage_nodes =
      cross_validation_nodes = [
        %Node{
          first_public_key: "key2",
          last_public_key: "key2",
          geo_patch: "AAA",
          ip: {127, 0, 0, 1},
          port: 3002,
          reward_address: :crypto.strong_rand_bytes(32),
          authorized?: true,
          available?: true,
          authorization_date: DateTime.utc_now() |> DateTime.add(-2)
        },
        %Node{
          first_public_key: "key3",
          last_public_key: "key3",
          geo_patch: "AAA",
          ip: {127, 0, 0, 1},
          port: 3003,
          reward_address: :crypto.strong_rand_bytes(32),
          authorized?: true,
          available?: true,
          authorization_date: DateTime.utc_now() |> DateTime.add(-2)
        }
      ]

    P2P.add_and_connect_node(welcome_node)
    P2P.add_and_connect_node(coordinator_node)
    Enum.each(cross_validation_nodes, &P2P.add_and_connect_node(&1))
    Enum.each(previous_storage_nodes, &P2P.add_and_connect_node(&1))

    unspent_outputs =
      [
        %UnspentOutput{
          from: "@Alice2",
          amount: 204_000_000,
          type: :UCO,
          timestamp: validation_time
        }
      ]
      |> VersionedUnspentOutput.wrap_unspent_outputs(current_protocol_version())

    %ValidationContext{
      transaction: TransactionFactory.create_non_valided_transaction(),
      previous_storage_nodes: previous_storage_nodes,
      unspent_outputs: unspent_outputs,
      aggregated_utxos: unspent_outputs,
      welcome_node: welcome_node,
      coordinator_node: coordinator_node,
      cross_validation_nodes: cross_validation_nodes,
      validation_time: validation_time
    }
  end

  defp create_validation_stamp_with_invalid_signature(%ValidationContext{
         transaction: tx,
         unspent_outputs: unspent_outputs,
         validation_time: timestamp
       }) do
    fee = Fee.calculate(tx, nil, 0.07, timestamp, nil, 0, current_protocol_version())

    movements = Transaction.get_movements(tx)
    resolved_addresses = Enum.map(movements, &{&1.to, &1.to}) |> Map.new()

    ledger_operations =
      %LedgerOperations{fee: fee}
      |> LedgerOperations.consume_inputs(
        tx.address,
        timestamp,
        unspent_outputs,
        movements,
        LedgerOperations.get_utxos_from_transaction(tx, timestamp, current_protocol_version())
      )
      |> elem(1)
      |> LedgerOperations.build_resolved_movements(movements, resolved_addresses, tx.type)

    %ValidationStamp{
      timestamp: timestamp,
      proof_of_work: Crypto.origin_node_public_key(),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations: ledger_operations,
      signature: :crypto.strong_rand_bytes(32),
      protocol_version: current_protocol_version()
    }
  end

  defp create_validation_stamp_with_invalid_proof_of_work(%ValidationContext{
         transaction: tx,
         unspent_outputs: unspent_outputs,
         validation_time: timestamp
       }) do
    fee = Fee.calculate(tx, nil, 0.07, timestamp, nil, 0, current_protocol_version())

    movements = Transaction.get_movements(tx)
    resolved_addresses = Enum.map(movements, &{&1.to, &1.to}) |> Map.new()

    ledger_operations =
      %LedgerOperations{fee: fee}
      |> LedgerOperations.consume_inputs(
        tx.address,
        timestamp,
        unspent_outputs,
        movements,
        LedgerOperations.get_utxos_from_transaction(tx, timestamp, current_protocol_version())
      )
      |> elem(1)
      |> LedgerOperations.build_resolved_movements(movements, resolved_addresses, tx.type)

    %ValidationStamp{
      timestamp: timestamp,
      proof_of_work: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations: ledger_operations,
      protocol_version: current_protocol_version()
    }
    |> ValidationStamp.sign()
  end

  defp create_validation_stamp(%ValidationContext{
         transaction: tx,
         unspent_outputs: unspent_outputs,
         validation_time: timestamp
       }) do
    fee = Fee.calculate(tx, nil, 0.07, timestamp, nil, 0, current_protocol_version())

    movements = Transaction.get_movements(tx)
    resolved_addresses = Enum.map(movements, &{&1.to, &1.to}) |> Map.new()

    ledger_operations =
      %LedgerOperations{fee: fee}
      |> LedgerOperations.consume_inputs(
        tx.address,
        timestamp,
        unspent_outputs,
        movements,
        LedgerOperations.get_utxos_from_transaction(tx, timestamp, current_protocol_version())
      )
      |> elem(1)
      |> LedgerOperations.build_resolved_movements(movements, resolved_addresses, tx.type)

    %ValidationStamp{
      timestamp: timestamp,
      proof_of_work: Crypto.origin_node_public_key(),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations: ledger_operations,
      protocol_version: current_protocol_version()
    }
    |> ValidationStamp.sign()
  end

  defp create_validation_stamp_with_invalid_transaction_fee(%ValidationContext{
         transaction: tx,
         unspent_outputs: unspent_outputs,
         validation_time: timestamp
       }) do
    movements = Transaction.get_movements(tx)
    resolved_addresses = Enum.map(movements, &{&1.to, &1.to}) |> Map.new()

    ledger_operations =
      %LedgerOperations{fee: 1}
      |> LedgerOperations.consume_inputs(
        tx.address,
        timestamp,
        unspent_outputs,
        movements,
        LedgerOperations.get_utxos_from_transaction(tx, timestamp, current_protocol_version())
      )
      |> elem(1)
      |> LedgerOperations.build_resolved_movements(movements, resolved_addresses, tx.type)

    %ValidationStamp{
      timestamp: timestamp,
      proof_of_work: Crypto.origin_node_public_key(),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations: ledger_operations,
      protocol_version: current_protocol_version()
    }
    |> ValidationStamp.sign()
  end

  defp create_validation_stamp_with_invalid_transaction_movements(%ValidationContext{
         transaction: tx,
         validation_time: timestamp,
         unspent_outputs: unspent_outputs
       }) do
    fee = Fee.calculate(tx, nil, 0.07, timestamp, nil, 0, current_protocol_version())

    ledger_operations = %LedgerOperations{
      fee: fee,
      transaction_movements: [
        %TransactionMovement{to: "@Bob3", amount: 200_000_000_000, type: :UCO}
      ],
      consumed_inputs: unspent_outputs,
      unspent_outputs: [
        %UnspentOutput{
          amount: Enum.reduce(unspent_outputs, 0, &(&1.unspent_output.amount + &2)) - fee,
          from: tx.address,
          type: :UCO,
          timestamp: timestamp
        }
      ]
    }

    %ValidationStamp{
      timestamp: timestamp,
      proof_of_work: Crypto.origin_node_public_key(),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations: ledger_operations,
      protocol_version: current_protocol_version()
    }
    |> ValidationStamp.sign()
  end

  defp create_validation_stamp_with_invalid_unspent_outputs(%ValidationContext{
         transaction: tx,
         unspent_outputs: unspent_outputs,
         validation_time: timestamp
       }) do
    %ValidationStamp{
      timestamp: timestamp,
      proof_of_work: Crypto.origin_node_public_key(),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations: %LedgerOperations{
        fee: Fee.calculate(tx, nil, 0.07, timestamp, nil, 0, current_protocol_version()),
        transaction_movements: Transaction.get_movements(tx),
        consumed_inputs: unspent_outputs,
        unspent_outputs: [
          %UnspentOutput{
            amount: 100_000_000_000,
            from: tx.address,
            type: :UCO,
            timestamp: timestamp
          }
        ]
      },
      protocol_version: current_protocol_version()
    }
    |> ValidationStamp.sign()
  end

  defp create_validation_stamp_with_invalid_errors(%ValidationContext{
         transaction: tx,
         unspent_outputs: unspent_outputs,
         validation_time: timestamp
       }) do
    fee = Fee.calculate(tx, nil, 0.07, timestamp, nil, 0, current_protocol_version())
    movements = Transaction.get_movements(tx)
    resolved_addresses = Enum.map(movements, &{&1.to, &1.to}) |> Map.new()

    ledger_operations =
      %LedgerOperations{fee: fee}
      |> LedgerOperations.consume_inputs(
        tx.address,
        timestamp,
        unspent_outputs,
        movements,
        LedgerOperations.get_utxos_from_transaction(tx, timestamp, current_protocol_version())
      )
      |> elem(1)
      |> LedgerOperations.build_resolved_movements(movements, resolved_addresses, tx.type)

    %ValidationStamp{
      timestamp: timestamp,
      proof_of_work: Crypto.origin_node_public_key(),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations: ledger_operations,
      error: :invalid_pending_transaction,
      protocol_version: current_protocol_version()
    }
    |> ValidationStamp.sign()
  end

  defp create_validation_stamp_with_invalid_consumed_inputs(%ValidationContext{
         transaction: tx,
         validation_time: timestamp,
         unspent_outputs: unspent_outputs
       }) do
    fee = Fee.calculate(tx, nil, 0.07, timestamp, nil, 0, current_protocol_version())
    movements = Transaction.get_movements(tx)
    resolved_addresses = Enum.map(movements, &{&1.to, &1.to}) |> Map.new()

    ledger_operations =
      %LedgerOperations{fee: fee}
      |> LedgerOperations.consume_inputs(
        tx.address,
        timestamp,
        unspent_outputs,
        movements,
        LedgerOperations.get_utxos_from_transaction(tx, timestamp, current_protocol_version())
      )
      |> elem(1)
      |> LedgerOperations.build_resolved_movements(movements, resolved_addresses, tx.type)
      |> Map.put(
        :consumed_inputs,
        [
          %UnspentOutput{
            amount: 100_000_000,
            from: random_address(),
            type: :UCO,
            timestamp: DateTime.add(timestamp, -1000)
          }
        ]
        |> VersionedUnspentOutput.wrap_unspent_outputs(current_protocol_version())
      )

    %ValidationStamp{
      timestamp: timestamp,
      proof_of_work: Crypto.origin_node_public_key(),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations: ledger_operations,
      protocol_version: current_protocol_version()
    }
    |> ValidationStamp.sign()
  end
end
