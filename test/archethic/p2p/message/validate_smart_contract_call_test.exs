defmodule Archethic.P2P.Message.ValidateSmartContractCallTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.Contracts.Contract.Failure

  alias Archethic.Mining.Fee
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.SmartContractCallValidation
  alias Archethic.P2P.Message.ValidateSmartContractCall
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.P2P.Message.GetUnspentOutputs

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer

  alias Archethic.ContractFactory
  alias Archethic.TransactionFactory

  alias Archethic.Utils

  doctest ValidateSmartContractCall

  import Mox
  import ArchethicCase

  describe "serialize/deserialize" do
    test "should work with unnamed action" do
      msg = %ValidateSmartContractCall{
        recipient: %Recipient{address: random_address()},
        transaction: Archethic.TransactionFactory.create_valid_transaction(),
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }

      assert {^msg, <<>>} =
               msg
               |> ValidateSmartContractCall.serialize()
               |> ValidateSmartContractCall.deserialize()
    end

    test "should work with named action" do
      msg = %ValidateSmartContractCall{
        recipient: %Recipient{address: random_address(), action: "do_it", args: []},
        transaction: Archethic.TransactionFactory.create_valid_transaction(),
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }

      assert {^msg, <<>>} =
               msg
               |> ValidateSmartContractCall.serialize()
               |> ValidateSmartContractCall.deserialize()
    end
  end

  describe "process/2" do
    setup do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3005,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1000),
        geo_patch: "AAA"
      })

      :ok
    end

    test "should validate smart contract call and return valid message" do
      tx =
        ~s"""
        @version 1

        condition triggered_by: transaction, as: [
          timestamp: transaction.timestamp > 0
        ]

        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
        """
        |> ContractFactory.create_valid_contract_tx(
          seed: "contract_without_named_action_with_valid_message"
        )

      MockDB
      |> expect(:get_transaction, fn "@SC1_for_contract_without_named_action_with_valid_message",
                                     _,
                                     _ ->
        {:ok, tx}
      end)

      incoming_tx = TransactionFactory.create_valid_transaction([], content: "hola")

      assert %SmartContractCallValidation{status: :ok} =
               %ValidateSmartContractCall{
                 recipient: %Recipient{
                   address: "@SC1_for_contract_without_named_action_with_valid_message"
                 },
                 transaction: incoming_tx,
                 timestamp: DateTime.utc_now()
               }
               |> ValidateSmartContractCall.process(:crypto.strong_rand_bytes(32))
    end

    test "should validate smart contract call with named action and return valid message" do
      tx =
        ~s"""
        @version 1

        condition triggered_by: transaction, on: upgrade(), as: []
        actions triggered_by: transaction, on: upgrade() do
          Contract.set_code transaction.content
        end
        """
        |> ContractFactory.create_valid_contract_tx(
          seed: "contract_with_named_action_and_valid_message"
        )

      MockDB
      |> expect(:get_transaction, fn "@SC1_for_contract_with_named_action_and_valid_message",
                                     _,
                                     _ ->
        {:ok, tx}
      end)

      incoming_tx = TransactionFactory.create_valid_transaction([], content: "hola")

      assert %SmartContractCallValidation{status: :ok} =
               %ValidateSmartContractCall{
                 recipient: %Recipient{
                   address: "@SC1_for_contract_with_named_action_and_valid_message",
                   action: "upgrade",
                   args: []
                 },
                 transaction: incoming_tx,
                 timestamp: DateTime.utc_now()
               }
               |> ValidateSmartContractCall.process(:crypto.strong_rand_bytes(32))
    end

    test "should return fee of generated transaction" do
      code = ~s"""
      @version 1

      condition triggered_by: transaction, as: [
        timestamp: transaction.timestamp > 0
      ]

      actions triggered_by: transaction do
        Contract.set_content "hello"
      end
      """

      tx = ContractFactory.create_valid_contract_tx(code, seed: "contract_with_test_for_fee")

      MockDB
      |> expect(:get_transaction, fn "@SC1_for_contract_with_test_for_fee", _, _ -> {:ok, tx} end)

      incoming_tx = TransactionFactory.create_valid_transaction([], content: "hola")

      expected_fee =
        ContractFactory.create_valid_contract_tx(code,
          content: "hello",
          seed: "contract_with_test_for_fee"
        )
        |> Fee.calculate(nil, 0.07, DateTime.utc_now(), nil, 0, current_protocol_version())

      assert %SmartContractCallValidation{status: :ok, fee: expected_fee} ==
               %ValidateSmartContractCall{
                 recipient: %Recipient{address: "@SC1_for_contract_with_test_for_fee"},
                 transaction: incoming_tx,
                 timestamp: DateTime.utc_now()
               }
               |> ValidateSmartContractCall.process(:crypto.strong_rand_bytes(32))
    end

    test "should NOT validate smart contract that does not have a transaction trigger" do
      tx =
        ~s"""
        @version 1

        actions triggered_by: datetime, at: 1687874880 do
          Contract.set_content 42
        end
        """
        |> ContractFactory.create_valid_contract_tx(seed: "contract_without_trigger_transaction")

      MockDB
      |> expect(:get_transaction, fn "@SC1_for_contract_without_trigger_transaction", _, _ ->
        {:ok, tx}
      end)

      incoming_tx = TransactionFactory.create_valid_transaction([], content: "hola")

      failure = %Failure{error: :missing_condition, user_friendly_error: "Missing condition"}

      assert %SmartContractCallValidation{status: {:error, :invalid_execution, ^failure}, fee: 0} =
               %ValidateSmartContractCall{
                 recipient: %Recipient{address: "@SC1_for_contract_without_trigger_transaction"},
                 transaction: incoming_tx,
                 timestamp: DateTime.utc_now()
               }
               |> ValidateSmartContractCall.process(:crypto.strong_rand_bytes(32))
    end

    test "should validate smart contract call and return invalid message" do
      tx =
        ~s"""
        @version 1

        condition triggered_by: transaction, as: [
          content: "hola"
        ]

        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
        """
        |> ContractFactory.create_valid_contract_tx(seed: "contract_with_invalid_message")

      MockDB
      |> expect(:get_transaction, fn "@SC1_for_contract_with_invalid_message", _, _ ->
        {:ok, tx}
      end)

      incoming_tx = TransactionFactory.create_valid_transaction([], content: "hi")

      assert %SmartContractCallValidation{status: {:error, :invalid_condition, "content"}, fee: 0} =
               %ValidateSmartContractCall{
                 recipient: %Recipient{address: "@SC1_for_contract_with_invalid_message"},
                 transaction: incoming_tx,
                 timestamp: DateTime.utc_now()
               }
               |> ValidateSmartContractCall.process(:crypto.strong_rand_bytes(32))
    end

    test "should return insufficient_funds if contract has not enough funds " do
      tx =
        %Transaction{address: contract_address} =
        ~s"""
        @version 1

        condition triggered_by: transaction, as: []

        actions triggered_by: transaction do
          amount = Map.get(transaction.uco_transfers, contract.address)
          Contract.add_uco_transfer to: transaction.address, amount: amount + 5
        end
        """
        |> ContractFactory.create_valid_contract_tx(seed: random_seed())

      contract_genesis_address = Transaction.previous_address(tx)

      v_utxo =
        %UnspentOutput{
          from: random_address(),
          amount: Utils.to_bigint(3),
          type: :UCO,
          timestamp: DateTime.utc_now()
        }
        |> VersionedUnspentOutput.wrap_unspent_output(current_protocol_version())

      utxo = %UnspentOutput{
        from: random_address(),
        amount: Utils.to_bigint(5),
        type: :UCO,
        timestamp: DateTime.utc_now()
      }

      recipient = %Recipient{address: contract_genesis_address}

      incoming_tx =
        TransactionFactory.create_valid_transaction([utxo],
          ledger: %Ledger{
            uco: %UCOLedger{transfers: [%Transfer{to: contract_address, amount: 4}]}
          },
          recipients: [recipient]
        )

      MockClient
      |> expect(:send_message, fn _, %GetUnspentOutputs{address: ^contract_genesis_address}, _ ->
        {:ok, %UnspentOutputList{unspent_outputs: [v_utxo]}}
      end)

      MockDB
      |> expect(:get_last_chain_address, fn ^contract_genesis_address ->
        {contract_address, DateTime.utc_now()}
      end)
      |> expect(:get_transaction, fn ^contract_address, _, _ ->
        {:ok, tx}
      end)

      assert %SmartContractCallValidation{status: {:error, :insufficient_funds}, fee: 0} =
               %ValidateSmartContractCall{
                 recipient: recipient,
                 transaction: incoming_tx,
                 timestamp: DateTime.utc_now()
               }
               |> ValidateSmartContractCall.process(:crypto.strong_rand_bytes(32))
    end

    test "should return :ok if contract has enough funds " do
      tx =
        %Transaction{address: contract_address} =
        ~s"""
        @version 1

        condition triggered_by: transaction, as: []

        actions triggered_by: transaction do
          amount = Map.get(transaction.uco_transfers, contract.address)
          Contract.add_uco_transfer to: transaction.address, amount: amount + 1
        end
        """
        |> ContractFactory.create_valid_contract_tx(seed: random_seed())

      contract_genesis_address = Transaction.previous_address(tx)

      v_utxo =
        %UnspentOutput{
          from: random_address(),
          amount: Utils.to_bigint(3),
          type: :UCO,
          timestamp: DateTime.utc_now()
        }
        |> VersionedUnspentOutput.wrap_unspent_output(current_protocol_version())

      utxo = %UnspentOutput{
        from: random_address(),
        amount: Utils.to_bigint(5),
        type: :UCO,
        timestamp: DateTime.utc_now()
      }

      recipient = %Recipient{address: contract_genesis_address}

      incoming_tx =
        TransactionFactory.create_valid_transaction([utxo],
          ledger: %Ledger{
            uco: %UCOLedger{transfers: [%Transfer{to: contract_address, amount: 4}]}
          },
          recipients: [recipient]
        )

      MockClient
      |> expect(:send_message, fn _, %GetUnspentOutputs{address: ^contract_genesis_address}, _ ->
        {:ok, %UnspentOutputList{unspent_outputs: [v_utxo]}}
      end)

      MockDB
      |> expect(:get_last_chain_address, fn ^contract_genesis_address ->
        {contract_address, DateTime.utc_now()}
      end)
      |> expect(:get_transaction, fn ^contract_address, _, _ ->
        {:ok, tx}
      end)

      assert %SmartContractCallValidation{status: :ok, fee: _} =
               %ValidateSmartContractCall{
                 recipient: recipient,
                 transaction: incoming_tx,
                 timestamp: DateTime.utc_now()
               }
               |> ValidateSmartContractCall.process(:crypto.strong_rand_bytes(32))
    end

    test "should return custom message when throw in condition" do
      tx =
        ~s"""
        @version 1

        condition triggered_by: transaction do
          throw code: 1234, message: "Custom message", data: [key: "custom data"]
        end

        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
        """
        |> ContractFactory.create_valid_contract_tx()

      MockDB
      |> expect(:get_transaction, fn "@SC1", _, _ -> {:ok, tx} end)

      incoming_tx = TransactionFactory.create_valid_transaction([], content: "hi")

      message = "Custom message - L4"

      data = %{
        "code" => 1234,
        "message" => "Custom message",
        "data" => %{"key" => "custom data"}
      }

      assert %SmartContractCallValidation{
               status:
                 {:error, :invalid_execution,
                  %Failure{user_friendly_error: ^message, error: :contract_throw, data: ^data}},
               fee: 0
             } =
               %ValidateSmartContractCall{
                 recipient: %Recipient{address: "@SC1"},
                 transaction: incoming_tx,
                 timestamp: DateTime.utc_now()
               }
               |> ValidateSmartContractCall.process(:crypto.strong_rand_bytes(32))
    end

    test "should return custom message when throw in action" do
      tx =
        ~s"""
        @version 1

        condition triggered_by: transaction do
          true
        end

        actions triggered_by: transaction do
          throw code: 1234, message: "Custom message", data: [key: "custom data"]
        end
        """
        |> ContractFactory.create_valid_contract_tx()

      MockDB
      |> expect(:get_transaction, fn "@SC1", _, _ -> {:ok, tx} end)

      incoming_tx = TransactionFactory.create_valid_transaction([], content: "hi")

      message = "Custom message - L8"

      data = %{
        "code" => 1234,
        "message" => "Custom message",
        "data" => %{"key" => "custom data"}
      }

      assert %SmartContractCallValidation{
               status:
                 {:error, :invalid_execution,
                  %Failure{user_friendly_error: ^message, error: :contract_throw, data: ^data}},
               fee: 0
             } =
               %ValidateSmartContractCall{
                 recipient: %Recipient{address: "@SC1"},
                 transaction: incoming_tx,
                 timestamp: DateTime.utc_now()
               }
               |> ValidateSmartContractCall.process(:crypto.strong_rand_bytes(32))
    end
  end
end
