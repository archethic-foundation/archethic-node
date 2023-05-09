defmodule Archethic.Contracts.InterpreterTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Interpreter
  alias Archethic.ContractFactory

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  doctest Interpreter

  describe "strict versionning" do
    test "should return ok if version exists" do
      assert {:ok, _} = Interpreter.parse(ContractFactory.valid_version1_contract())
      assert {:ok, _} = Interpreter.parse(ContractFactory.valid_legacy_contract())
    end

    test "should return an error if version does not exist yet" do
      code_v0 = ~s"""
      @version 20
      #{ContractFactory.valid_legacy_contract()}
      """

      code_v1 = ~s"""
      @version 20
      #{ContractFactory.valid_version1_contract(version_attribute: false)}
      """

      assert {:error, "@version not supported"} = Interpreter.parse(code_v0)
      assert {:error, "@version not supported"} = Interpreter.parse(code_v1)
    end

    test "should return an error if version is invalid" do
      code_v0 = ~s"""
      @version 1.5
      #{ContractFactory.valid_legacy_contract()}
      """

      assert {:error, "@version not supported"} = Interpreter.parse(code_v0)
    end
  end

  describe "parse code v1" do
    test "should return an error if there are unexpected terms" do
      assert {:error, _} =
               """
               @version 1
               condition inherit: [
                content: true
               ]
               condition transaction: [
                uco_transfers: List.size() > 0
               ]

               some_unexpected_code

               actions triggered_by: transaction do
                Contract.set_content "hello"
               end
               """
               |> Interpreter.parse()
    end

    test "should return the contract if format is OK" do
      assert {:ok, %Contract{}} =
               """
               @version 1
               condition inherit: [
                content: true
               ]
               condition transaction: [
                uco_transfers: List.size() > 0
               ]
               actions triggered_by: transaction do
                Contract.set_content "hello"
               end
               """
               |> Interpreter.parse()
    end

    test "should return an human readable error if lib fn is called with bad arg" do
      assert {:error, "invalid function arguments - List.empty?(12) - L5"} =
               """
               @version 1
               condition inherit: []
               condition transaction: []
               actions triggered_by: transaction do
                 x = List.empty?(12)
               end
               """
               |> Interpreter.parse()
    end

    test "should return an human readable error if lib fn is called with bad arity" do
      assert {:error, "invalid function arity - List.empty?([1], \"foobar\") - L5"} =
               """
               @version 1
               condition inherit: []
               condition transaction: []
               actions triggered_by: transaction do
                 x = List.empty?([1], "foobar")
               end
               """
               |> Interpreter.parse()
    end

    test "should return an human readable error if lib fn does not exists" do
      assert {:error, "unknown function - List.non_existing([1, 2, 3]) - L5"} =
               """
               @version 1
               condition inherit: []
               condition transaction: []
               actions triggered_by: transaction do
                 x = List.non_existing([1,2,3])
               end
               """
               |> Interpreter.parse()
    end

    test "should return an human readable error if syntax is not elixir-valid" do
      assert {:error, "Parse error: invalid language syntax"} =
               """
               @version 1
               actions triggered_by:transaction do
                x = "missing space above"
               end
               """
               |> Interpreter.parse()
    end

    test "should return an human readable error 'condition inherit' block is missing" do
      assert {:error, "missing 'condition inherit' block"} =
               """
               @version 1
               condition transaction: []
               actions triggered_by: transaction do
                Contract.set_content "symptomatic grizzly bear"
               end
               """
               |> Interpreter.parse()
    end

    test "should return an human readable error 'condition transaction' block is missing" do
      assert {:error, "missing 'condition transaction' block"} =
               """
               @version 1
               condition inherit: []
               actions triggered_by: transaction do
                Contract.set_content "snobbish chameleon"
               end
               """
               |> Interpreter.parse()
    end

    test "should return an human readable error 'condition oracle' block is missing" do
      assert {:error, "missing 'condition oracle' block"} =
               """
               @version 1
               condition inherit: []
               actions triggered_by: oracle do
                Contract.set_content "wise cow"
               end
               """
               |> Interpreter.parse()
    end
  end

  describe "parse code v0" do
    test "should return an error if there are unexpected terms" do
      assert {:error, _} =
               """
               condition transaction: [
                uco_transfers: size() > 0
               ]

               some_unexpected_code

               actions triggered_by: transaction do
                set_content "hello"
               end
               """
               |> Interpreter.parse()
    end

    test "should return the contract if format is OK" do
      assert {:ok, %Contract{}} =
               """
               condition inherit: [
                content: true
               ]
               condition transaction: [
                uco_transfers: size() > 0
               ]

               actions triggered_by: transaction do
                set_content "hello"
               end
               """
               |> Interpreter.parse()
    end
  end

  describe "execute/3" do
    test "should return a transaction if the contract is correct and there was a Contract.* call" do
      code = """
        @version 1
        condition inherit: [
          content: "hello"
        ]

        condition transaction: []

        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
      """

      contract_tx = %Transaction{
        type: :contract,
        data: %TransactionData{
          code: code
        }
      }

      incoming_tx = %Transaction{
        type: :transfer,
        data: %TransactionData{},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      assert {:ok, %Transaction{}} =
               Interpreter.execute(
                 :transaction,
                 Contract.from_transaction!(contract_tx),
                 incoming_tx,
                 [incoming_tx]
               )
    end

    test "should return nil when the contract is correct but no Contract.* call" do
      code = """
        @version 1
        condition inherit: [
          content: "hello"
        ]

        condition transaction: []

        actions triggered_by: transaction do
          if false do
            Contract.set_content "hello"
          end
        end
      """

      contract_tx = %Transaction{
        type: :contract,
        data: %TransactionData{
          code: code
        }
      }

      incoming_tx = %Transaction{
        type: :transfer,
        data: %TransactionData{},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      assert {:ok, nil} =
               Interpreter.execute(
                 :transaction,
                 Contract.from_transaction!(contract_tx),
                 incoming_tx,
                 [incoming_tx]
               )
    end

    test "should return inherit constraints error when condition inherit fails" do
      code = """
        @version 1
        condition inherit: [
          content: "hello",
          type: "data"
        ]

        condition transaction: []

        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
      """

      contract_tx = %Transaction{
        type: :contract,
        data: %TransactionData{
          code: code
        }
      }

      incoming_tx = %Transaction{
        type: :transfer,
        data: %TransactionData{},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      assert match?(
               {:error, :invalid_inherit_constraints},
               Interpreter.execute(
                 :transaction,
                 Contract.from_transaction!(contract_tx),
                 incoming_tx,
                 [incoming_tx]
               )
             )
    end

    test "should return transaction constraints error when condition inherit fails" do
      code = """
        @version 1
        condition inherit: [
          content: true
        ]

        condition transaction: [
          type: "data"
        ]

        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
      """

      contract_tx = %Transaction{
        type: :contract,
        data: %TransactionData{
          code: code
        }
      }

      incoming_tx = %Transaction{
        type: :transfer,
        data: %TransactionData{},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      assert match?(
               {:error, :invalid_transaction_constraints},
               Interpreter.execute(
                 :transaction,
                 Contract.from_transaction!(contract_tx),
                 incoming_tx,
                 [incoming_tx]
               )
             )
    end

    test "should return oracle constraints error when condition oracle fails" do
      code = """
        @version 1
        condition inherit: [
          content: true
        ]

        condition oracle: [
          type: "oracle",
          address: false
        ]

        actions triggered_by: oracle do
          Contract.set_content "hello"
        end
      """

      contract_tx = %Transaction{
        type: :contract,
        data: %TransactionData{
          code: code
        }
      }

      oracle_tx = %Transaction{
        type: :oracle,
        data: %TransactionData{},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      assert match?(
               {:error, :invalid_oracle_constraints},
               Interpreter.execute(
                 :oracle,
                 Contract.from_transaction!(contract_tx),
                 oracle_tx,
                 [oracle_tx]
               )
             )
    end

    test "should return contract_failure if contract code crash" do
      code = """
        @version 1
        condition inherit: [
          content: true
        ]

        condition transaction: []

        actions triggered_by: transaction do
          x = 10 / 0
          Contract.set_content x
        end
      """

      contract_tx = %Transaction{
        type: :contract,
        data: %TransactionData{
          code: code
        }
      }

      incoming_tx = %Transaction{
        type: :transfer,
        data: %TransactionData{},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      assert match?(
               {:error, :contract_failure},
               Interpreter.execute(
                 :transaction,
                 Contract.from_transaction!(contract_tx),
                 incoming_tx,
                 [incoming_tx]
               )
             )

      code = """
        @version 1
        condition inherit: [
          content: true
        ]

        condition transaction: []

        actions triggered_by: transaction do
          Contract.add_uco_transfer amount: -1, to: "0000BFEF73346D20771614449D6BE9C705BF314067A0CF0ACBBF5E617EF5C978D0A1"
        end
      """

      contract_tx = %Transaction{
        type: :contract,
        data: %TransactionData{
          code: code
        }
      }

      assert match?(
               {:error, :contract_failure},
               Interpreter.execute(
                 :transaction,
                 Contract.from_transaction!(contract_tx),
                 incoming_tx,
                 [incoming_tx]
               )
             )
    end

    test "should be able to simulate a trigger: datetime" do
      code = """
        @version 1
        condition inherit: [
          content: "hello"
        ]

        actions triggered_by: datetime, at: 1678984136 do
          Contract.set_content "hello"
        end
      """

      contract_tx = %Transaction{
        type: :contract,
        data: %TransactionData{
          code: code
        }
      }

      assert {:ok, %Transaction{}} =
               Interpreter.execute(
                 {:datetime, ~U[2023-03-16 16:28:56Z]},
                 Contract.from_transaction!(contract_tx),
                 nil,
                 []
               )
    end

    test "should be able to simulate a trigger: interval" do
      code = """
        @version 1
        condition inherit: [
          content: "hello"
        ]

        actions triggered_by: interval, at: "* * * * *" do
          Contract.set_content "hello"
        end
      """

      contract_tx = %Transaction{
        type: :contract,
        data: %TransactionData{
          code: code
        }
      }

      assert {:ok, %Transaction{}} =
               Interpreter.execute(
                 {:interval, "* * * * *"},
                 Contract.from_transaction!(contract_tx),
                 nil,
                 []
               )
    end

    test "should be able to simulate a trigger: oracle" do
      code = """
        @version 1
        condition inherit: [
          content: "hello"
        ]

        condition oracle: []

        actions triggered_by: oracle do
          Contract.set_content "hello"
        end
      """

      contract_tx = %Transaction{
        type: :contract,
        data: %TransactionData{
          code: code
        }
      }

      oracle_tx = %Transaction{
        type: :oracle,
        data: %TransactionData{},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      assert {:ok, %Transaction{}} =
               Interpreter.execute(
                 :oracle,
                 Contract.from_transaction!(contract_tx),
                 oracle_tx,
                 [oracle_tx]
               )
    end

    test "should be able to get_calls" do
      code = ~s"""
      @version 1
      condition inherit: [
        content: true
      ]

      condition transaction: []

      actions triggered_by: transaction do
        calls = Contract.get_calls()
        Contract.set_content List.size(calls)
      end
      """

      contract_tx = %Transaction{
        type: :contract,
        data: %TransactionData{
          code: code
        }
      }

      incoming_tx = %Transaction{
        type: :transfer,
        data: %TransactionData{},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      calls = [
        %Transaction{
          type: :transfer,
          data: %TransactionData{}
        },
        %Transaction{
          type: :transfer,
          data: %TransactionData{}
        },
        %Transaction{
          type: :transfer,
          data: %TransactionData{}
        },
        incoming_tx
      ]

      assert {:ok, %Transaction{data: %TransactionData{content: "4"}}} =
               Interpreter.execute(
                 :transaction,
                 Contract.from_transaction!(contract_tx),
                 incoming_tx,
                 calls
               )
    end
  end
end
