defmodule Archethic.Replication.TransactionValidatorTest do
  use ArchethicCase, async: false

  alias Archethic.ContractFactory
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Contract.State
  alias Archethic.Crypto
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

  describe "validate/1" do
    test "should return {:error, :invalid_atomic_commitment} when the atomic commitment is not reached" do
      unspent_outputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        }
      ]

      assert {:error, :invalid_atomic_commitment} =
               TransactionFactory.create_transaction_with_not_atomic_commitment(unspent_outputs)
               |> TransactionValidator.validate()
    end

    test "should return {:error, :invalid_proof_of_work} when an invalid proof of work" do
      assert {:error, :invalid_proof_of_work} =
               TransactionFactory.create_transaction_with_invalid_proof_of_work()
               |> TransactionValidator.validate()
    end

    test "should return {:error, :invalid_node_election} when the validation stamp signature is invalid" do
      assert {:error, :invalid_node_election} =
               TransactionFactory.create_transaction_with_invalid_validation_stamp_signature()
               |> TransactionValidator.validate()
    end

    test "should return {:error, :invalid_transaction_movements} when the transaction movements are invalid" do
      assert {:error, :invalid_transaction_movements} =
               TransactionFactory.create_transaction_with_invalid_transaction_movements()
               |> TransactionValidator.validate()
    end

    test "should return {:error, :invalid_transaction_with_inconsistencies} when there is an atomic commitment but with inconsistencies" do
      unspent_outputs = [
        %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        }
      ]

      assert {:error, :invalid_transaction_with_inconsistencies} =
               TransactionFactory.create_valid_transaction_with_inconsistencies(unspent_outputs)
               |> TransactionValidator.validate()
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

      assert :ok =
               TransactionFactory.create_valid_transaction(unspent_outputs)
               |> TransactionValidator.validate()
    end
  end

  describe "validate/5" do
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

      tx = TransactionFactory.create_valid_transaction(unspent_outputs)
      genesis = Transaction.previous_address(tx)

      assert :ok = TransactionValidator.validate(tx, nil, genesis, v_unspent_outputs, nil)
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

      assert :ok =
               TransactionValidator.validate(
                 next_tx,
                 prev_tx,
                 genesis,
                 versioned_inputs,
                 %Contract.Context{
                   status: :tx_output,
                   timestamp: now,
                   trigger: {:datetime, now}
                 }
               )
    end

    test "should return {:error, :invalid_transaction_fee} when the fees are invalid" do
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

      assert {:error, :invalid_transaction_fee} =
               TransactionValidator.validate(tx, nil, genesis, v_unspent_outputs, nil)
    end

    test "should return {:error, :invalid_transaction_fee} when the fees are invalid using contract context" do
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
        timestamp: DateTime.utc_now()
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

      assert {:error, :invalid_transaction_fee} =
               TransactionValidator.validate(
                 next_tx,
                 prev_tx,
                 contract_genesis,
                 v_unspent_outputs,
                 contract_context
               )
    end

    test "should return {:error, :invalid_recipients_execution} if recipient contract execution invalid" do
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
        {:ok, %SmartContractCallValidation{valid?: false, fee: 0}}
      end)
      |> expect(:send_message, fn _, %GetGenesisAddress{address: ^recipient_address}, _ ->
        {:ok, %GenesisAddress{address: recipient_genesis, timestamp: DateTime.utc_now()}}
      end)

      assert {:error, :invalid_recipients_execution} =
               TransactionValidator.validate(tx, nil, genesis, v_unspent_outputs, nil)
    end
  end
end
