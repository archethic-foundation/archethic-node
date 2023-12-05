defmodule Archethic.Contracts.Interpreter.ConditionValidatorTest do
  use ArchethicCase

  alias Archethic.ContractFactory
  alias Archethic.Contracts.Constants
  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.ConditionInterpreter
  alias Archethic.Contracts.Interpreter.ConditionValidator
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Reward.MemTables.RewardTokens
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer
  alias Archethic.TransactionFactory

  setup do
    start_supervised!(RewardTokens)
    :ok
  end

  describe "execute_condition/2" do
    test "should return ok if the transaction's conditions are valid" do
      code = ~s"""
      condition triggered_by: transaction, as: [
        type: "transfer"
      ]
      """

      tx = TransactionFactory.create_valid_transaction([])

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "transaction" => Constants.from_transaction(tx)
               })
    end

    test "should return ok if the inherit's conditions are valid" do
      code = ~s"""
      condition inherit: [
        content: "Hello"
      ]
      """

      previous_tx = ContractFactory.create_valid_contract_tx(code)
      next_tx = ContractFactory.create_next_contract_tx(previous_tx, content: "Hello")

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "previous" => Constants.from_contract_transaction(previous_tx),
                 "next" => Constants.from_contract_transaction(next_tx)
               })
    end

    test "should return ok if the oracle's conditions are valid" do
      code = ~s"""
      condition triggered_by: oracle, as: [
        content: "Hello"
      ]
      """

      tx = TransactionFactory.create_valid_transaction([], content: "Hello")

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "transaction" => Constants.from_transaction(tx)
               })
    end

    test "should return ok with a flexible condition" do
      code = ~s"""
      condition inherit: [
        content: true
      ]
      """

      previous_tx = ContractFactory.create_valid_contract_tx(code)
      next_tx = ContractFactory.create_next_contract_tx(previous_tx, content: "Hello")

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "previous" => Constants.from_contract_transaction(previous_tx),
                 "next" => Constants.from_contract_transaction(next_tx)
               })
    end

    test "should return error if modifying a value not in the condition" do
      code = ~s"""
      condition inherit: []
      """

      previous_tx = ContractFactory.create_valid_contract_tx(code)
      next_tx = ContractFactory.create_next_contract_tx(previous_tx, content: "Hello")

      assert {:error, "content", _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "previous" => Constants.from_contract_transaction(previous_tx),
                 "next" => Constants.from_contract_transaction(next_tx)
               })
    end

    test "should be able to use boolean expression in inherit" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      condition inherit: [
        uco_transfers: Map.size() == 1
      ]
      """

      previous_tx = ContractFactory.create_valid_contract_tx(code)

      ledger = %Ledger{
        uco: %UCOLedger{
          transfers: [%UCOTransfer{amount: Archethic.Utils.to_bigint(1), to: address}]
        }
      }

      next_tx = ContractFactory.create_next_contract_tx(previous_tx, ledger: ledger)

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "previous" => Constants.from_contract_transaction(previous_tx),
                 "next" => Constants.from_contract_transaction(next_tx)
               })

      code = ~s"""
      condition inherit: [
        uco_transfers: Map.size() == 3
      ]
      """

      assert {:error, "uco_transfers", _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "previous" => Constants.from_contract_transaction(previous_tx),
                 "next" => Constants.from_contract_transaction(next_tx)
               })
    end

    test "should cast bigint to float" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      token_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      condition triggered_by: transaction, as: [
        uco_transfers: (
          transaction.uco_transfers["#{Base.encode16(address)}"] == 1
        ),
        token_transfers: (
          transfers_at_address = transaction.token_transfers["#{Base.encode16(address)}"]
          first_transfer = List.at(transfers_at_address, 0)
          first_transfer.amount == 1
        )
      ]
      """

      ledger = %Ledger{
        uco: %UCOLedger{
          transfers: [%UCOTransfer{amount: Archethic.Utils.to_bigint(1), to: address}]
        },
        token: %TokenLedger{
          transfers: [
            %TokenTransfer{
              token_id: 0,
              token_address: token_address,
              amount: Archethic.Utils.to_bigint(1),
              to: address
            }
          ]
        }
      }

      tx = TransactionFactory.create_valid_transaction([], ledger: ledger)

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "transaction" => Constants.from_transaction(tx)
               })
    end

    test "should be able to use boolean expression in transaction" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      ledger = %Ledger{
        uco: %UCOLedger{
          transfers: [%UCOTransfer{amount: Archethic.Utils.to_bigint(1), to: address}]
        }
      }

      tx = TransactionFactory.create_valid_transaction([], ledger: ledger)

      code = ~s"""
      condition triggered_by: transaction, as: [
        uco_transfers: Map.size() > 0
      ]
      """

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "transaction" => Constants.from_transaction(tx)
               })

      code = ~s"""
      condition triggered_by: transaction, as: [
        uco_transfers: Map.size() == 1
      ]
      """

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "transaction" => Constants.from_transaction(tx)
               })

      code = ~s"""
      condition triggered_by: transaction, as: [
        uco_transfers: Map.size() == 2
      ]
      """

      assert {:error, "uco_transfers", _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "transaction" => Constants.from_transaction(tx)
               })

      code = ~s"""
      condition triggered_by: transaction, as: [
        uco_transfers: Map.size() < 10
      ]
      """

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "transaction" => Constants.from_transaction(tx)
               })
    end

    test "should be able to use dot access" do
      code = ~s"""
      condition inherit: [
          content: previous.content == next.content
      ]
      """

      previous_tx = ContractFactory.create_valid_contract_tx(code, content: "zoubida")
      next_tx = ContractFactory.create_next_contract_tx(previous_tx, content: "zoubida")

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "previous" => Constants.from_contract_transaction(previous_tx),
                 "next" => Constants.from_contract_transaction(next_tx)
               })

      code = ~s"""
      condition inherit: [
        content: previous.content == next.content
      ]
      """

      previous_tx = ContractFactory.create_valid_contract_tx(code, content: "lavabo")
      next_tx = ContractFactory.create_next_contract_tx(previous_tx, content: "bidet")

      assert {:error, "content", _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "previous" => Constants.from_contract_transaction(previous_tx),
                 "next" => Constants.from_contract_transaction(next_tx)
               })
    end

    test "should evaluate AST" do
      code = ~s"""
      condition inherit: [
        content: if true do "Hello" else "World" end
      ]
      """

      previous_tx = ContractFactory.create_valid_contract_tx(code)
      next_tx = ContractFactory.create_next_contract_tx(previous_tx, content: "Hello")

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "previous" => Constants.from_contract_transaction(previous_tx),
                 "next" => Constants.from_contract_transaction(next_tx)
               })

      code = ~s"""
      condition inherit: [
        content: if false do "Hello" else "World" end
      ]
      """

      previous_tx = ContractFactory.create_valid_contract_tx(code)
      next_tx = ContractFactory.create_next_contract_tx(previous_tx, content: "World")

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "previous" => Constants.from_contract_transaction(previous_tx),
                 "next" => Constants.from_contract_transaction(next_tx)
               })

      code = ~s"""
      condition inherit: [
        content: if false do "Hello" else "World" end
      ]
      """

      previous_tx = ContractFactory.create_valid_contract_tx(code)
      next_tx = ContractFactory.create_next_contract_tx(previous_tx, content: "Hello")

      assert {:error, "content", _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "previous" => Constants.from_contract_transaction(previous_tx),
                 "next" => Constants.from_contract_transaction(next_tx)
               })
    end

    test "should be able to use variables in the AST" do
      code = ~s"""
      condition inherit: [
        content: (
          x = 1
          x == 1
        )
      ]
      """

      previous_tx = ContractFactory.create_valid_contract_tx(code)
      next_tx = ContractFactory.create_next_contract_tx(previous_tx, content: "smthg")

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "previous" => Constants.from_contract_transaction(previous_tx),
                 "next" => Constants.from_contract_transaction(next_tx)
               })
    end

    test "should be able to use for loops" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      condition inherit: [
        uco_transfers: (
          found = false

          # search for a transfer of 1 uco to address
          for address in Map.keys(next.uco_transfers) do
            if address == "#{Base.encode16(address)}" && next.uco_transfers[address] == 1 do
              found = true
            end
          end

          found
        )
      ]
      """

      previous_tx = ContractFactory.create_valid_contract_tx(code)

      ledger = %Ledger{
        uco: %UCOLedger{
          transfers: [
            %UCOTransfer{amount: Archethic.Utils.to_bigint(1), to: address}
          ]
        }
      }

      next_tx = ContractFactory.create_next_contract_tx(previous_tx, ledger: ledger)

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "previous" => Constants.from_contract_transaction(previous_tx),
                 "next" => Constants.from_contract_transaction(next_tx)
               })
    end
  end

  describe "execute_condition/2 transaction with do..end" do
    test "should be able to return true" do
      code = ~s"""
      condition triggered_by: transaction do
        transaction.type == "transfer"
      end
      """

      tx = TransactionFactory.create_valid_transaction([])

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "transaction" => Constants.from_transaction(tx)
               })
    end

    test "should be able to return false" do
      code = ~s"""
      condition triggered_by: transaction do
        transaction.type == "data"
      end
      """

      tx = TransactionFactory.create_valid_transaction([])

      assert {:error, "N/A", []} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "transaction" => Constants.from_transaction(tx)
               })
    end

    test "should be able to throw" do
      code = ~s"""
      condition triggered_by: transaction do
        throw code: 4, message: "Something went wrong"
      end
      """

      tx = TransactionFactory.create_valid_transaction([])

      assert_raise Library.ErrorContractThrow, "Something went wrong", fn ->
        code
        |> Interpreter.sanitize_code()
        |> elem(1)
        |> ConditionInterpreter.parse([])
        |> elem(2)
        |> ConditionValidator.execute_condition(%{
          "transaction" => Constants.from_transaction(tx)
        })
      end
    end

    test "should be able to call private function" do
      code = ~s"""
      condition triggered_by: transaction do
        transaction.type == allowed_type()
      end

      fun allowed_type() do
        "transfer"
      end
      """

      tx = TransactionFactory.create_valid_transaction([])

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "transaction" => Constants.from_transaction(tx)
               })
    end
  end

  describe "execute_condition/2 oracle with do..end" do
    test "should return truthy" do
      code = ~s"""
      condition triggered_by: oracle do
        transaction.content == "Hello"
      end
      """

      tx = TransactionFactory.create_valid_transaction([], content: "Hello")

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "transaction" => Constants.from_transaction(tx)
               })
    end

    test "should return falsy" do
      code = ~s"""
      condition triggered_by: oracle do
        transaction.content == "Hello"
      end
      """

      tx = TransactionFactory.create_valid_transaction([], content: "Heyho")

      assert {:error, "N/A", []} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "transaction" => Constants.from_transaction(tx)
               })
    end
  end

  describe "execute_condition/2 inherit with do..end" do
    test "should return truthy" do
      code = ~s"""
      condition inherit do
        previous.content == next.content
      end
      """

      prev = TransactionFactory.create_valid_transaction([], content: "Hello")
      next = TransactionFactory.create_valid_transaction([], content: "Hello")

      assert {:ok, _logs} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "previous" => Constants.from_transaction(prev),
                 "next" => Constants.from_transaction(next)
               })
    end

    test "should return falsy" do
      code = ~s"""
      condition inherit do
        previous.content == next.content
      end
      """

      prev = TransactionFactory.create_valid_transaction([], content: "Hi")
      next = TransactionFactory.create_valid_transaction([], content: "Hello")

      assert {:error, "N/A", []} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
               |> elem(2)
               |> ConditionValidator.execute_condition(%{
                 "previous" => Constants.from_transaction(prev),
                 "next" => Constants.from_transaction(next)
               })
    end
  end
end
