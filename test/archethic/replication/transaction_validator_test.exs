defmodule Archethic.Replication.TransactionValidatorTest do
  use ArchethicCase, async: false

  alias Archethic.ContractFactory
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Contract.State
  alias Archethic.Crypto
  alias Archethic.Mining.Error
  alias Archethic.Mining.ValidationContext
  alias Archethic.P2P
  alias Archethic.P2P.Message.GetLastTransactionAddress
  alias Archethic.P2P.Message.LastTransactionAddress
  alias Archethic.P2P.Message.SmartContractCallValidation
  alias Archethic.P2P.Message.ValidateSmartContractCall
  alias Archethic.P2P.Message.GetGenesisAddress
  alias Archethic.P2P.Message.GenesisAddress
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Node
  alias Archethic.Replication.TransactionValidator
  alias Archethic.SharedSecrets
  alias Archethic.SharedSecrets.MemTables.NetworkLookup
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.ContractFactory
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionFactory

  import ArchethicCase
  import Mox

  @moduletag :capture_log

  setup do
    SharedSecrets.add_origin_public_key(:software, Crypto.first_node_public_key())

    Crypto.generate_deterministic_keypair("daily_nonce_seed")
    |> elem(0)
    |> NetworkLookup.set_daily_nonce_public_key(DateTime.utc_now() |> DateTime.add(-10))

    welcome_node = %Node{
      first_public_key: random_public_key(),
      last_public_key: random_public_key(),
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-1),
      available?: true,
      geo_patch: "BBB",
      network_patch: "BBB"
    }

    coordinator_node = %Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-1),
      geo_patch: "AAA",
      network_patch: "AAA"
    }

    storage_nodes = [
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: random_public_key(),
        last_public_key: random_public_key(),
        authorized?: true,
        available?: true,
        geo_patch: "BBB",
        network_patch: "BBB",
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      }
    ]

    Enum.each(storage_nodes, &P2P.add_and_connect_node(&1))

    P2P.add_and_connect_node(welcome_node)
    P2P.add_and_connect_node(coordinator_node)

    {:ok,
     %{
       welcome_node: welcome_node,
       coordinator_node: coordinator_node,
       storage_nodes: storage_nodes
     }}
  end

  describe "validate_consensus/1" do
    test "should return error when the atomic commitment is not reached" do
      unspent_outputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        }
      ]

      tx = TransactionFactory.create_transaction_with_not_atomic_commitment(unspent_outputs)

      validation_context = %ValidationContext{
        transaction: tx,
        validation_stamp: tx.validation_stamp
      }

      assert %ValidationContext{mining_error: %Error{data: "Invalid atomic commitment"}} =
               TransactionValidator.validate_consensus(validation_context)
    end

    test "should return error when an invalid proof of work" do
      tx = TransactionFactory.create_transaction_with_invalid_proof_of_work()

      validation_context = %ValidationContext{
        transaction: tx,
        validation_stamp: tx.validation_stamp
      }

      assert %ValidationContext{mining_error: %Error{data: "Invalid proof of work"}} =
               TransactionValidator.validate_consensus(validation_context)
    end

    test "should return error when the validation stamp signature is invalid" do
      tx = TransactionFactory.create_transaction_with_invalid_validation_stamp_signature()

      validation_context = %ValidationContext{
        transaction: tx,
        validation_stamp: tx.validation_stamp
      }

      assert %ValidationContext{mining_error: %Error{data: "Invalid election"}} =
               TransactionValidator.validate_consensus(validation_context)
    end

    test "should return error when there is an atomic commitment but with inconsistencies" do
      unspent_outputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        }
      ]

      tx = TransactionFactory.create_valid_transaction_with_inconsistencies(unspent_outputs)

      validation_context = %ValidationContext{
        transaction: tx,
        validation_stamp: tx.validation_stamp
      }

      assert %ValidationContext{mining_error: %Error{data: "Invalid atomic commitment"}} =
               TransactionValidator.validate_consensus(validation_context)
    end

    test "should return :ok when the transaction is valid" do
      unspent_outputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        }
      ]

      tx = TransactionFactory.create_valid_transaction(unspent_outputs)

      validation_context = %ValidationContext{
        transaction: tx,
        validation_stamp: tx.validation_stamp
      }

      assert %ValidationContext{mining_error: nil} =
               TransactionValidator.validate_consensus(validation_context)
    end
  end

  describe "validate/1" do
    test "should return :ok when the transaction is valid" do
      unspent_outputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        }
      ]

      v_unspent_outputs =
        VersionedUnspentOutput.wrap_unspent_outputs(unspent_outputs, current_protocol_version())

      tx =
        TransactionFactory.create_valid_transaction(unspent_outputs,
          type: :data,
          content: "content"
        )

      genesis = Transaction.previous_address(tx)

      validation_context = %ValidationContext{
        transaction: tx,
        previous_transaction: nil,
        genesis_address: genesis,
        aggregated_utxos: v_unspent_outputs,
        unspent_outputs: v_unspent_outputs,
        contract_context: nil,
        validation_stamp: tx.validation_stamp,
        validation_time: tx.validation_stamp.timestamp
      }

      assert %ValidationContext{mining_error: nil} =
               TransactionValidator.validate(validation_context)
    end

    test "should validate when the transaction coming from a contract is valid" do
      now = ~U[2023-01-01 00:00:00Z]

      code = """
      @version 1

      actions triggered_by: datetime, at: #{DateTime.to_unix(now)} do
        State.set("key", "value")
        Contract.set_content "ok"
      end
      """

      encoded_state = State.serialize(%{"key" => "value"})

      prev_tx = ContractFactory.create_valid_contract_tx(code)

      inputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        }
      ]

      versioned_inputs =
        VersionedUnspentOutput.wrap_unspent_outputs(inputs, current_protocol_version())

      next_tx =
        ContractFactory.create_next_contract_tx(prev_tx,
          content: "ok",
          state: encoded_state,
          inputs: inputs
        )

      genesis = Transaction.previous_address(prev_tx)

      contract_context = %Contract.Context{
        status: :tx_output,
        timestamp: now,
        trigger: {:datetime, now},
        inputs: versioned_inputs
      }

      validation_context = %ValidationContext{
        transaction: next_tx,
        previous_transaction: prev_tx,
        genesis_address: genesis,
        aggregated_utxos: versioned_inputs,
        unspent_outputs: versioned_inputs,
        contract_context: contract_context,
        validation_stamp: next_tx.validation_stamp,
        validation_time: next_tx.validation_stamp.timestamp
      }

      assert %ValidationContext{mining_error: nil} =
               TransactionValidator.validate(validation_context)
    end

    test "should return error when the fees are invalid" do
      unspent_outputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        }
      ]

      tx = TransactionFactory.create_transaction_with_invalid_fee(unspent_outputs)
      genesis = Transaction.previous_address(tx)

      v_unspent_outputs =
        VersionedUnspentOutput.wrap_unspent_outputs(unspent_outputs, current_protocol_version())

      validation_context = %ValidationContext{
        transaction: tx,
        previous_transaction: nil,
        genesis_address: genesis,
        aggregated_utxos: v_unspent_outputs,
        unspent_outputs: v_unspent_outputs,
        contract_context: nil,
        validation_stamp: tx.validation_stamp,
        validation_time: tx.validation_stamp.timestamp
      }

      assert %ValidationContext{mining_error: %Error{data: ["transaction fee"]}} =
               TransactionValidator.validate(validation_context)
    end

    test "should return error when the fees are invalid using contract context" do
      contract_seed = "seed"

      contract_genesis =
        contract_seed |> Crypto.derive_keypair(0) |> elem(0) |> Crypto.derive_address()

      recipient = %Recipient{action: "test", args: [], address: contract_genesis}

      trigger_tx =
        %Transaction{address: trigger_address} =
        TransactionFactory.create_valid_transaction([], recipients: [recipient])

      unspent_outputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        },
        %UnspentOutput{
          from: trigger_address,
          amount: nil,
          type: :call,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        }
      ]

      v_unspent_outputs =
        VersionedUnspentOutput.wrap_unspent_outputs(unspent_outputs, current_protocol_version())

      contract_context = %Contract.Context{
        trigger: {:transaction, trigger_address, recipient},
        status: :tx_output,
        timestamp: DateTime.utc_now(),
        inputs: Contract.Context.filter_inputs(v_unspent_outputs)
      }

      code = """
        @version 1
        condition triggered_by: transaction, on: test(), as: []
        actions triggered_by: transaction, on: test() do
          Contract.set_content("ok")
        end
      """

      prev_tx = ContractFactory.create_valid_contract_tx(code, seed: contract_seed)

      next_tx =
        ContractFactory.create_next_contract_tx(prev_tx,
          content: "ok",
          inputs: unspent_outputs,
          contract_context: contract_context
        )

      MockClient
      |> stub(:send_message, fn _, %GetTransaction{address: ^trigger_address}, _ ->
        {:ok, trigger_tx}
      end)

      validation_context = %ValidationContext{
        transaction: next_tx,
        previous_transaction: prev_tx,
        genesis_address: contract_genesis,
        aggregated_utxos: v_unspent_outputs,
        unspent_outputs: v_unspent_outputs,
        contract_context: contract_context,
        validation_stamp: next_tx.validation_stamp,
        validation_time: next_tx.validation_stamp.timestamp
      }

      assert %ValidationContext{mining_error: %Error{data: ["transaction fee"]}} =
               TransactionValidator.validate(validation_context)
    end

    test "should return error if recipient contract execution invalid" do
      unspent_outputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        }
      ]

      v_unspent_outputs =
        VersionedUnspentOutput.wrap_unspent_outputs(unspent_outputs, current_protocol_version())

      recipient_address = random_address()
      recipient_genesis = random_address()
      recipient = %Recipient{address: recipient_address}
      tx = TransactionFactory.create_valid_transaction(unspent_outputs, recipients: [recipient])

      genesis = Transaction.previous_address(tx)

      MockClient
      |> expect(:send_message, fn _, %GetLastTransactionAddress{}, _ ->
        {:ok, %LastTransactionAddress{address: random_address()}}
      end)
      |> expect(:send_message, fn _, %ValidateSmartContractCall{}, _ ->
        {:ok,
         %SmartContractCallValidation{
           status: {:error, :invalid_condition, "content"},
           fee: 0,
           last_chain_sync_date: DateTime.utc_now()
         }}
      end)
      |> expect(:send_message, fn _, %GetGenesisAddress{address: ^recipient_address}, _ ->
        {:ok, %GenesisAddress{address: recipient_genesis, timestamp: DateTime.utc_now()}}
      end)

      validation_context = %ValidationContext{
        transaction: tx,
        previous_transaction: nil,
        genesis_address: genesis,
        aggregated_utxos: v_unspent_outputs,
        unspent_outputs: v_unspent_outputs,
        contract_context: nil,
        validation_stamp: tx.validation_stamp,
        validation_time: tx.validation_stamp.timestamp,
        resolved_addresses: %{recipient_address => recipient_genesis}
      }

      assert %ValidationContext{mining_error: %Error{message: "Invalid recipients execution"}} =
               TransactionValidator.validate(validation_context)
    end

    test "should return error when the inputs are invalid using contract context" do
      contract_seed = "seed"

      contract_genesis =
        contract_seed |> Crypto.derive_keypair(0) |> elem(0) |> Crypto.derive_address()

      recipient = %Recipient{action: "test", args: [], address: contract_genesis}

      trigger_tx =
        %Transaction{address: trigger_address} =
        TransactionFactory.create_valid_transaction([], recipients: [recipient])

      unspent_outputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        },
        %UnspentOutput{
          from: trigger_address,
          amount: nil,
          type: :call,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        }
      ]

      v_unspent_outputs =
        VersionedUnspentOutput.wrap_unspent_outputs(unspent_outputs, current_protocol_version())

      contract_context = %Contract.Context{
        trigger: {:transaction, trigger_address, recipient},
        status: :tx_output,
        timestamp: DateTime.utc_now(),
        inputs: []
      }

      code = """
        @version 1
        condition triggered_by: transaction, on: test(), as: []
        actions triggered_by: transaction, on: test() do
          Contract.set_content("ok")
        end
      """

      prev_tx = ContractFactory.create_valid_contract_tx(code, seed: contract_seed)

      next_tx =
        ContractFactory.create_next_contract_tx(prev_tx,
          content: "ok",
          inputs: unspent_outputs,
          contract_context: contract_context
        )

      MockClient
      |> stub(:send_message, fn _, %GetTransaction{address: ^trigger_address}, _ ->
        {:ok, trigger_tx}
      end)

      validation_context = %ValidationContext{
        transaction: next_tx,
        previous_transaction: prev_tx,
        genesis_address: contract_genesis,
        aggregated_utxos: v_unspent_outputs,
        unspent_outputs: v_unspent_outputs,
        contract_context: contract_context,
        validation_stamp: next_tx.validation_stamp,
        validation_time: next_tx.validation_stamp.timestamp
      }

      assert %ValidationContext{mining_error: %Error{message: "Invalid contract context inputs"}} =
               TransactionValidator.validate(validation_context)
    end
  end
end
