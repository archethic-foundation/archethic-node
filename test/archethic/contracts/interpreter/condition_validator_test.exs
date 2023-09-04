defmodule Archethic.Contracts.Interpreter.ConditionValidatorTest do
  use ArchethicCase

  alias Archethic.Contracts.ContractConstants, as: Constants
  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.ConditionInterpreter

  alias Archethic.Contracts.Interpreter.ConditionValidator
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer

  describe "valid_conditions?/2" do
    test "should return true if the transaction's conditions are valid" do
      code = ~s"""
      condition triggered_by: transaction, as: [
        type: "transfer"
      ]
      """

      tx = %Transaction{
        type: :transfer,
        data: %TransactionData{}
      }

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "transaction" => Constants.from_transaction(tx)
             })
    end

    test "should return true if the inherit's conditions are valid" do
      code = ~s"""
      condition inherit: [
        content: "Hello"
      ]
      """

      previous_tx = %Transaction{data: %TransactionData{}}
      next_tx = %Transaction{data: %TransactionData{content: "Hello"}}

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "previous" => Constants.from_transaction(previous_tx),
               "next" => Constants.from_transaction(next_tx)
             })
    end

    test "should return true if the oracle's conditions are valid" do
      code = ~s"""
      condition triggered_by: oracle, as: [
        content: "Hello"
      ]
      """

      tx = %Transaction{
        data: %TransactionData{
          content: "Hello"
        }
      }

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "transaction" => Constants.from_transaction(tx)
             })
    end

    test "should return true with a flexible condition" do
      code = ~s"""
      condition inherit: [
        content: true
      ]
      """

      previous_tx = %Transaction{data: %TransactionData{}}
      next_tx = %Transaction{data: %TransactionData{content: "Hello"}}

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "previous" => Constants.from_transaction(previous_tx),
               "next" => Constants.from_transaction(next_tx)
             })
    end

    test "should return false if modifying a value not in the condition" do
      code = ~s"""
      condition inherit: []
      """

      previous_tx = %Transaction{data: %TransactionData{}}
      next_tx = %Transaction{data: %TransactionData{content: "Hello"}}

      refute code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "previous" => Constants.from_transaction(previous_tx),
               "next" => Constants.from_transaction(next_tx)
             })
    end

    test "should be able to use boolean expression in inherit" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      condition inherit: [
        uco_transfers: Map.size() == 1
      ]
      """

      previous_tx = %Transaction{data: %TransactionData{}}

      next_tx = %Transaction{
        data: %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %UCOTransfer{amount: Archethic.Utils.to_bigint(1), to: address}
              ]
            }
          }
        }
      }

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "previous" => Constants.from_transaction(previous_tx),
               "next" => Constants.from_transaction(next_tx)
             })

      code = ~s"""
      condition inherit: [
        uco_transfers: Map.size() == 3
      ]
      """

      next_tx = %Transaction{data: %TransactionData{}}

      refute code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "previous" => Constants.from_transaction(previous_tx),
               "next" => Constants.from_transaction(next_tx)
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

      tx = %Transaction{
        data: %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %UCOTransfer{amount: Archethic.Utils.to_bigint(1), to: address}
              ]
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
        }
      }

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "transaction" => Constants.from_transaction(tx)
             })
    end

    test "should be able to use boolean expression in transaction" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      tx = %Transaction{
        data: %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %UCOTransfer{amount: Archethic.Utils.to_bigint(1), to: address}
              ]
            }
          }
        }
      }

      code = ~s"""
      condition triggered_by: transaction, as: [
        uco_transfers: Map.size() > 0
      ]
      """

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "transaction" => Constants.from_transaction(tx)
             })

      code = ~s"""
      condition triggered_by: transaction, as: [
        uco_transfers: Map.size() == 1
      ]
      """

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "transaction" => Constants.from_transaction(tx)
             })

      code = ~s"""
      condition triggered_by: transaction, as: [
        uco_transfers: Map.size() == 2
      ]
      """

      refute code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "transaction" => Constants.from_transaction(tx)
             })

      code = ~s"""
      condition triggered_by: transaction, as: [
        uco_transfers: Map.size() < 10
      ]
      """

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "transaction" => Constants.from_transaction(tx)
             })
    end

    test "should be able to use dot access" do
      code = ~s"""
      condition inherit: [
          content: previous.content == next.content
      ]
      """

      previous_tx = %Transaction{data: %TransactionData{content: "zoubida"}}
      next_tx = %Transaction{data: %TransactionData{content: "zoubida"}}

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "previous" => Constants.from_transaction(previous_tx),
               "next" => Constants.from_transaction(next_tx)
             })

      code = ~s"""
      condition inherit: [
        content: previous.content == next.content
      ]
      """

      previous_tx = %Transaction{data: %TransactionData{content: "lavabo"}}
      next_tx = %Transaction{data: %TransactionData{content: "bidet"}}

      refute code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "previous" => Constants.from_transaction(previous_tx),
               "next" => Constants.from_transaction(next_tx)
             })
    end

    test "should evaluate AST" do
      code = ~s"""
      condition inherit: [
        content: if true do "Hello" else "World" end
      ]
      """

      previous_tx = %Transaction{data: %TransactionData{}}
      next_tx = %Transaction{data: %TransactionData{content: "Hello"}}

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "previous" => Constants.from_transaction(previous_tx),
               "next" => Constants.from_transaction(next_tx)
             })

      code = ~s"""
      condition inherit: [
        content: if false do "Hello" else "World" end
      ]
      """

      previous_tx = %Transaction{data: %TransactionData{}}
      next_tx = %Transaction{data: %TransactionData{content: "World"}}

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "previous" => Constants.from_transaction(previous_tx),
               "next" => Constants.from_transaction(next_tx)
             })

      code = ~s"""
      condition inherit: [
        content: if false do "Hello" else "World" end
      ]
      """

      previous_tx = %Transaction{data: %TransactionData{}}
      next_tx = %Transaction{data: %TransactionData{content: "Hello"}}

      refute code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "previous" => Constants.from_transaction(previous_tx),
               "next" => Constants.from_transaction(next_tx)
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

      previous_tx = %Transaction{data: %TransactionData{}}
      next_tx = %Transaction{data: %TransactionData{content: "smthg"}}

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "previous" => Constants.from_transaction(previous_tx),
               "next" => Constants.from_transaction(next_tx)
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

      previous_tx = %Transaction{data: %TransactionData{}}

      next_tx = %Transaction{
        data: %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %UCOTransfer{amount: Archethic.Utils.to_bigint(1), to: address}
              ]
            }
          }
        }
      }

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse([])
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "previous" => Constants.from_transaction(previous_tx),
               "next" => Constants.from_transaction(next_tx)
             })
    end
  end
end
