defmodule Archethic.P2P.Message.ValidateSmartContractCallTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.Mining.Fee
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.SmartContractCallValidation
  alias Archethic.P2P.Message.ValidateSmartContractCall

  alias Archethic.TransactionChain.TransactionData.Recipient

  alias Archethic.ContractFactory
  alias Archethic.TransactionFactory

  doctest ValidateSmartContractCall

  import Mox
  import ArchethicCase

  describe "serialize/deserialize" do
    test "should work with unnamed action" do
      msg = %ValidateSmartContractCall{
        recipient: %Recipient{address: random_address()},
        transaction: Archethic.TransactionFactory.create_valid_transaction(),
        inputs_before: DateTime.utc_now() |> DateTime.truncate(:millisecond)
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
        inputs_before: DateTime.utc_now() |> DateTime.truncate(:millisecond)
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
                 inputs_before: DateTime.utc_now()
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
                 inputs_before: DateTime.utc_now()
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
                 inputs_before: DateTime.utc_now()
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

      assert %SmartContractCallValidation{status: {:error, :invalid_execution}, fee: 0} =
               %ValidateSmartContractCall{
                 recipient: %Recipient{address: "@SC1_for_contract_without_trigger_transaction"},
                 transaction: incoming_tx,
                 inputs_before: DateTime.utc_now()
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

      assert %SmartContractCallValidation{status: {:error, :invalid_execution}, fee: 0} =
               %ValidateSmartContractCall{
                 recipient: %Recipient{address: "@SC1_for_contract_with_invalid_message"},
                 transaction: incoming_tx,
                 inputs_before: DateTime.utc_now()
               }
               |> ValidateSmartContractCall.process(:crypto.strong_rand_bytes(32))
    end
  end
end
