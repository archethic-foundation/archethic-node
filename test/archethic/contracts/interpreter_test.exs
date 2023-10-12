defmodule Archethic.Contracts.InterpreterTest do
  @moduledoc false
  use ArchethicCase
  import ArchethicCase

  alias Archethic.Contracts.Contract.State
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.ContractConstants, as: Constants
  alias Archethic.Contracts.ContractConditions, as: Conditions
  alias Archethic.Contracts.Interpreter
  alias Archethic.ContractFactory

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient

  alias Archethic.TransactionFactory

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
               condition triggered_by: transaction, as: [
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
               condition triggered_by: transaction, as: [
                uco_transfers: List.size() > 0
               ]
               actions triggered_by: transaction do
                Contract.set_content "hello"
               end
               """
               |> Interpreter.parse()
    end

    test "should return an human readable error if lib fn is called with bad arg" do
      assert {:error, "invalid function arguments - List.empty?/1 - L4"} =
               """
               @version 1
               condition triggered_by: transaction, as: []
               actions triggered_by: transaction do
                 x = List.empty?(12)
               end
               """
               |> Interpreter.parse()
    end

    test "should be able to use custom functions" do
      assert {:ok, _} =
               """
               @version 1

               fun hello_world() do
                  "hello world"
               end

               condition triggered_by: transaction, as: []
               actions triggered_by: transaction do
                 x = hello_world()
                 x
               end

               """
               |> Interpreter.parse()
    end

    test "should be able to use custom functions with args" do
      assert {:ok, _} =
               """
               @version 1

               fun sum(a,b) do
                 a + t
               end

               condition triggered_by: transaction, as: []
               actions triggered_by: transaction do
                 x = sum(5,6)
                 x
               end

               """
               |> Interpreter.parse()
    end

    test "should be able to use custom functions no matter the declaration order" do
      assert {:ok, _} =
               """
               @version 1

               export fun hello() do
                  "hello world"
               end

               condition triggered_by: transaction, as: []
               actions triggered_by: transaction do
                 hey()
               end

               fun hey() do
                  hello()
               end


               """
               |> Interpreter.parse()
    end

    test "should return an human readable error if custom function does not exist" do
      assert {:error, "The function hello_world/0 does not exist - hello_world - L9"} =
               """
               @version 1

               fun hello() do
                  "hello world"
               end

               condition triggered_by: transaction, as: []
               actions triggered_by: transaction do
                 x = hello_world()
                 x
               end

               """
               |> Interpreter.parse()
    end

    test "should return an human readable error if custom fn is called with bad arity" do
      assert {:error, "The function hello_world/1 does not exist - hello_world - L9"} =
               """
               @version 1

               fun hello_world() do
                  "hello world"
               end

               condition triggered_by: transaction, as: []
               actions triggered_by: transaction do
                 x = hello_world(1)
                 x
               end

               """
               |> Interpreter.parse()
    end

    test "should return an human readable error if lib fn is called with bad arity" do
      assert {:error,
              "Function List.empty? does not exists with 2 arguments - List.empty?/2 - L4"} =
               """
               @version 1
               condition triggered_by: transaction, as: []
               actions triggered_by: transaction do
                 x = List.empty?([1], "foobar")
               end
               """
               |> Interpreter.parse()
    end

    test "should return an human readable error if lib fn does not exists" do
      assert {:error, "Function List.non_existing does not exists - List.non_existing/1 - L4"} =
               """
               @version 1
               condition triggered_by: transaction, as: []
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
               condition triggered_by: transaction, as: []
               actions triggered_by:transaction do
                x = "missing space above"
               end
               """
               |> Interpreter.parse()
    end

    test "should return an human readable error 'condition transaction' block is missing" do
      assert {:error, "missing 'condition triggered_by: transaction' block"} =
               """
               @version 1
               actions triggered_by: transaction do
                Contract.set_content "snobbish chameleon"
               end
               """
               |> Interpreter.parse()
    end

    test "should return an human readable error 'condition oracle' block is missing" do
      assert {:error, "missing 'condition triggered_by: oracle' block"} =
               """
               @version 1
               actions triggered_by: oracle do
                Contract.set_content "wise cow"
               end
               """
               |> Interpreter.parse()
    end

    test "should return an human readable error 'condition triggered_by: transaction, on: xxx' block is missing" do
      assert {:error, "missing 'condition triggered_by: transaction, on: upgrade/0' block"} =
               """
               @version 1
               actions triggered_by: transaction, on: upgrade() do
                Contract.set_code transaction.content
               end
               """
               |> Interpreter.parse()

      assert {:error, "missing 'condition triggered_by: transaction, on: vote/2' block"} =
               """
               @version 1
               actions triggered_by: transaction, on: vote(x, y) do
                Contract.set_code transaction.content
               end
               """
               |> Interpreter.parse()

      assert {:error, "missing 'condition triggered_by: transaction, on: vote/2' block"} =
               """
               @version 1
               actions triggered_by: transaction, on: vote(x,y) do
                Contract.set_code transaction.content
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

  describe "execute_trigger/5" do
    test "should return an error if the trigger is not found" do
      code = """
      @version 1
      condition triggered_by: transaction, as: []
      actions triggered_by: transaction do
        Contract.set_content "hello"
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([])

      assert {:error, "Trigger not found on the contract"} =
               Interpreter.execute_trigger(
                 {:transaction, "function", []},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 incoming_tx,
                 nil
               )
    end

    test "should return a transaction if the contract is correct and there was a Contract.* call" do
      code = """
        @version 1
        condition triggered_by: transaction, as: []
        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([])

      assert {:ok, %Transaction{}, _state, _logs} =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 incoming_tx,
                 nil
               )

      code = """
        @version 1

        condition triggered_by: transaction, as: []
        actions triggered_by: transaction do
          Contract.set_content "hello"
        end

      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([])

      assert {
               :ok,
               %Transaction{
                 data: %TransactionData{
                   content: "hello"
                 }
               },
               _state,
               _logs
             } =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 incoming_tx,
                 nil
               )
    end

    test "should execute a contract v0 with constants" do
      code = """
      condition transaction: []
      actions triggered_by: transaction do
        toto = transaction.address
        set_content toto
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx =
        %Transaction{address: tx_address} = TransactionFactory.create_valid_transaction([])

      tx_address_hex = Base.encode16(tx_address)

      assert {
               :ok,
               %Transaction{
                 data: %TransactionData{
                   content: ^tx_address_hex
                 }
               },
               _state,
               _logs
             } =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 incoming_tx,
                 nil
               )
    end

    test "should be able to use a custom function call as parameter" do
      code = """
      @version 1

      fun hello_world() do
         "hello world"
      end

        condition triggered_by: transaction, as: []
      actions triggered_by: transaction do
        Contract.set_content hello_world()
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([])

      assert {
               :ok,
               %Transaction{
                 data: %TransactionData{
                   content: "hello world"
                 }
               },
               _state,
               _logs
             } =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 incoming_tx,
                 nil
               )
    end

    test "Should not be able to use out of scope variables" do
      code = """
        @version 1
        condition triggered_by: transaction, as: []
        actions triggered_by: transaction do
          my_var = "toto"
          Contract.set_content my_func()
        end

        fun my_func() do
          my_var
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([])

      assert {:error, _, _, _} =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 incoming_tx,
                 nil
               )

      code = """
        @version 1
        condition triggered_by: transaction, as: []
        actions triggered_by: transaction do
          temp = func1()
          Contract.set_content func2()
        end

        export fun func1() do
          my_var = "content"
        end

        fun func2() do
          my_var
        end

      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([])

      assert {:error, _, _, _} =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 incoming_tx,
                 nil
               )
    end

    test "Should be able to use variables from scope in functions" do
      code = """
        @version 1
        condition triggered_by: transaction, as: []
        actions triggered_by: transaction do
          Contract.set_content my_func()
        end

        fun my_func() do
          my_var = ""
          if true do
            my_var = "toto"
          end
          my_var
        end

      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([])

      assert {:ok, _, _state, _logs} =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 incoming_tx,
                 nil
               )
    end

    test "Should be able to use variables as args for custom functions" do
      code = """
        @version 1
        condition triggered_by: transaction, as: []
        actions triggered_by: transaction do
          salary = 1000
          tax = 0.7
          Contract.set_content net_income(salary, tax)
        end

        fun net_income(salary, tax) do
          salary - (salary * tax)
        end

      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([])

      assert {
               :ok,
               %Transaction{
                 data: %TransactionData{
                   content: "300"
                 }
               },
               _state,
               _logs
             } =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 incoming_tx,
                 nil
               )
    end

    test "Should be able to use module function calls as args for custom functions" do
      code = """
        @version 1
        condition triggered_by: transaction, as: []
        actions triggered_by: transaction do
          Contract.set_content counter(String.to_number(contract.content))
        end

        export fun counter(current_val) do
          current_val + 1
        end

      """

      contract_tx = ContractFactory.create_valid_contract_tx(code, content: "4")

      incoming_tx = TransactionFactory.create_valid_transaction([])

      assert {
               :ok,
               %Transaction{
                 data: %TransactionData{
                   content: "5"
                 }
               },
               _state,
               _logs
             } =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 incoming_tx,
                 nil
               )
    end

    test "Should be able to use custom function calls as args for custom functions" do
      code = """
        @version 1
        condition triggered_by: transaction, as: []
        actions triggered_by: transaction do
          Contract.set_content counter(other_function())
        end

        export fun counter(current_val) do
          current_val + 1
        end

        fun other_function() do
          4
        end

      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([])

      assert {
               :ok,
               %Transaction{
                 data: %TransactionData{
                   content: "5"
                 }
               },
               _state,
               _logs
             } =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 incoming_tx,
                 nil
               )
    end

    test "Should be able to use string interpolation as arg for custom functions" do
      code = ~S"""
        @version 1
        condition triggered_by: transaction, as: []
        actions triggered_by: transaction do
          name = "Toto"
          Contract.set_content hello("my name is #{name}")
        end

        export fun hello(phrase) do
          phrase
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([])

      assert {
               :ok,
               %Transaction{
                 data: %TransactionData{
                   content: "my name is Toto"
                 }
               },
               _state,
               _logs
             } =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 incoming_tx,
                 nil
               )
    end

    test "Should be able to calculate arg before passing it to custom functions" do
      code = """
        @version 1
        condition triggered_by: transaction, as: []
        actions triggered_by: transaction do
          name = "Toto"
          Contract.set_content sum_a_b(1 + 5, 4)
        end

        export fun sum_a_b(a, b) do
          a + b
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([])

      assert {
               :ok,
               %Transaction{
                 data: %TransactionData{
                   content: "10"
                 }
               },
               _state,
               _logs
             } =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 incoming_tx,
                 nil
               )
    end

    test "should return nil when the contract is correct but no Contract.* call" do
      code = """
        @version 1
        condition triggered_by: transaction, as: []
        actions triggered_by: transaction do
          if false do
            Contract.set_content "hello"
          end
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([])

      assert {:ok, nil, _state, _logs} =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 incoming_tx,
                 nil
               )
    end

    test "should return an error if contract code crash" do
      code = """
        @version 1
        condition triggered_by: transaction, as: []

        actions triggered_by: transaction do
          x = 10 / 0
          Contract.set_content x
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([])

      assert {:error, _, _, _} =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 incoming_tx,
                 nil
               )

      code = """
        @version 1
        condition triggered_by: transaction, as: []

        actions triggered_by: transaction do
          Contract.add_uco_transfer amount: -1, to: "0000BFEF73346D20771614449D6BE9C705BF314067A0CF0ACBBF5E617EF5C978D0A1"
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      assert {:error, _, _, _} =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 incoming_tx,
                 nil
               )
    end

    test "should be able to simulate a trigger: datetime" do
      code = """
        @version 1
        actions triggered_by: datetime, at: 1678984140 do
          Contract.set_content "hello"
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      assert {:ok, %Transaction{}, _state, _logs} =
               Interpreter.execute_trigger(
                 {:datetime, ~U[2023-03-16 16:29:00Z]},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 nil,
                 nil
               )
    end

    test "should be able to simulate a trigger: interval" do
      code = """
        @version 1
        actions triggered_by: interval, at: "* * * * *" do
          Contract.set_content "hello"
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      assert {:ok, %Transaction{}, _state, _logs} =
               Interpreter.execute_trigger(
                 {:interval, "* * * * *"},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 nil,
                 nil
               )
    end

    test "should be able to simulate a trigger: oracle" do
      code = """
        @version 1
        condition triggered_by: oracle, as: []
        actions triggered_by: oracle do
          Contract.set_content "hello"
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      oracle_tx = TransactionFactory.create_valid_transaction([], type: :oracle)

      assert {:ok, %Transaction{}, _state, _logs} =
               Interpreter.execute_trigger(
                 :oracle,
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 oracle_tx,
                 nil
               )
    end

    test "should be able to use a named action argument in the action & condition blocks" do
      code = """
        @version 1
        condition triggered_by: transaction, on: vote(candidate), as: [
          content: candidate == "Dr. Who?"
        ]
        actions triggered_by: transaction, on: vote(candidate) do
          Contract.set_content candidate
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      recipient = %Recipient{address: contract_tx.address, action: "vote", args: ["Dr. Who?"]}
      recipients = [recipient, %Recipient{address: random_address()}]

      trigger_tx =
        TransactionFactory.create_valid_transaction([], type: :data, recipients: recipients)

      trigger_key = Contract.get_trigger_for_recipient(recipient)

      assert {:ok, %Transaction{data: %TransactionData{content: "Dr. Who?"}}, _state, _logs} =
               Interpreter.execute_trigger(
                 trigger_key,
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 trigger_tx,
                 List.first(trigger_tx.data.recipients)
               )
    end

    test "Should not be able to overwrite protected global variables" do
      code = """
        @version 1
        condition triggered_by: transaction, as: []
        actions triggered_by: transaction do
          time_now = 2_000_000_000
          Contract.set_content Time.now()
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      incoming_tx = TransactionFactory.create_valid_transaction([])

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {
               :ok,
               %Transaction{
                 data: %TransactionData{
                   content: content
                 }
               },
               _state,
               _logs
             } =
               Interpreter.execute_trigger(
                 {:transaction, nil, nil},
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 incoming_tx,
                 nil,
                 time_now: now
               )

      assert String.to_integer(content) == DateTime.to_unix(now)
    end

    test "should be able to use a named action arguments in the action & condition blocks" do
      code = """
        @version 1
        condition triggered_by: transaction, on: add(x, y), as: []
        actions triggered_by: transaction, on: add(x, y) do
          Contract.set_content x + y
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      recipient = %Recipient{address: contract_tx.address, action: "add", args: [1, 2]}

      trigger_tx =
        TransactionFactory.create_valid_transaction([], type: :data, recipients: [recipient])

      trigger_key = Contract.get_trigger_for_recipient(recipient)

      assert {:ok, %Transaction{data: %TransactionData{content: "3"}}, _state, _logs} =
               Interpreter.execute_trigger(
                 trigger_key,
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 trigger_tx,
                 List.first(trigger_tx.data.recipients)
               )
    end

    test "should be able to have different spacing in condition & actions named action" do
      code = """
        @version 1
        condition triggered_by: transaction, on: add(x,      y), as: []
        actions triggered_by: transaction, on: add(x,y) do
          Contract.set_content x + y
        end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      recipient = %Recipient{address: contract_tx.address, action: "add", args: [1, 2]}

      trigger_tx =
        TransactionFactory.create_valid_transaction([], type: :data, recipients: [recipient])

      trigger_key = Contract.get_trigger_for_recipient(recipient)

      assert {:ok, %Transaction{data: %TransactionData{content: "3"}}, _state, _logs} =
               Interpreter.execute_trigger(
                 trigger_key,
                 Contract.from_transaction!(contract_tx),
                 State.empty(),
                 trigger_tx,
                 List.first(trigger_tx.data.recipients)
               )
    end

    test "should be able to read and update the contract state from an action block" do
      code = """
      @version 1
      actions triggered_by: datetime, at: 0 do
        counter = State.get("counter")
        State.set("counter", counter + 1)
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      assert {:ok, nil, %{"counter" => 45}, _logs} =
               Interpreter.execute_trigger(
                 {:datetime, DateTime.from_unix!(0)},
                 Contract.from_transaction!(contract_tx),
                 %{"counter" => 44},
                 nil,
                 nil
               )
    end

    test "should be able to read the contract state from a condition block" do
      code = """
      @version 1
      condition triggered_by: transaction, as: [
        content: transaction.content == State.get("password")
      ]
      actions triggered_by: transaction do
        Contract.set_content "ok"
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)
      trigger_tx = TransactionFactory.create_valid_transaction([], content: "p4ssw0rd")
      contract = Contract.from_transaction!(contract_tx)

      %Conditions{subjects: subjects} = Map.get(contract.conditions, {:transaction, nil, nil})

      constants = %{
        "transaction" => Constants.from_transaction(trigger_tx),
        state: %{
          "password" => "p4ssw0rd"
        }
      }

      assert Interpreter.valid_conditions?(
               1,
               subjects,
               constants
             )
    end

    test "should be able to read the contract state from a private function block" do
      code = """
      @version 1
      actions triggered_by: datetime, at: 0 do
        if read_counter() == 44 do
          Contract.set_content "ok"
        end
      end

      fun read_counter() do
        State.get("counter")
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      assert {:ok, %Transaction{data: %TransactionData{content: "ok"}}, _state, _logs} =
               Interpreter.execute_trigger(
                 {:datetime, DateTime.from_unix!(0)},
                 Contract.from_transaction!(contract_tx),
                 %{"counter" => 44},
                 nil,
                 nil
               )
    end

    test "should be able to read the contract state from a public function block" do
      code = """
      @version 1
      actions triggered_by: datetime, at: 0 do
        if read_counter() == 44 do
          Contract.set_content "ok"
        end
      end

      export fun read_counter() do
        State.get("counter")
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      assert {:ok, %Transaction{data: %TransactionData{content: "ok"}}, _state, _logs} =
               Interpreter.execute_trigger(
                 {:datetime, DateTime.from_unix!(0)},
                 Contract.from_transaction!(contract_tx),
                 %{"counter" => 44},
                 nil,
                 nil
               )
    end

    test "should be able to have complex state" do
      code = """
      @version 1
      actions triggered_by: datetime, at: 0 do
        a = State.get("a")
        b = Map.get(a, "b")
        c = Map.get(b, "c")
        c = List.append(c, 4)
        b = Map.set(b, "c", c)
        a = Map.set(a, "b", b)
        State.set("a", a)
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      assert {:ok, nil, %{"a" => %{"b" => %{"c" => [1, 2, 3, 4]}}}, _logs} =
               Interpreter.execute_trigger(
                 {:datetime, DateTime.from_unix!(0)},
                 Contract.from_transaction!(contract_tx),
                 %{"a" => %{"b" => %{"c" => [1, 2, 3]}}},
                 nil,
                 nil
               )
    end
  end

  describe "sanitize_code/1" do
    test "should transform atom into tuple {:atom, \"value\"}" do
      code = """
      @version 1
      condition triggered_by: transaction, as: [
        address: "0xabc123def456"
      ]
      """

      assert {:ok, ast} = Interpreter.sanitize_code(code)

      assert match?(
               {:__block__, [],
                [
                  {_, _, [{{:atom, "version"}, _, _}]},
                  {{:atom, "condition"}, _,
                   [
                     [
                       {{:atom, "triggered_by"}, {{:atom, "transaction"}, _, nil}},
                       {{:atom, "as"}, [{{:atom, "address"}, "0xabc123def456"}]}
                     ]
                   ]}
                ]},
               ast
             )
    end

    test "should transform 0x hex in uppercase string" do
      code = """
      @version 1
      condition triggered_by: transaction, as: [
        address: 0xabc123def456
      ]
      """

      assert {:ok, ast} = Interpreter.sanitize_code(code)

      assert match?(
               {:__block__, [],
                [
                  {_, _, [{{:atom, "version"}, _, _}]},
                  {{:atom, "condition"}, _,
                   [
                     [
                       {{:atom, "triggered_by"}, {{:atom, "transaction"}, _, nil}},
                       {{:atom, "as"}, [{{:atom, "address"}, "ABC123DEF456"}]}
                     ]
                   ]}
                ]},
               ast
             )
    end

    test "should return an error when 0x format is not hexadecimal" do
      code = """
      @version 1
      condition triggered_by: transaction, as: [
        address: 0xnothexa
      ]
      """

      assert {:error, {[line: _, column: _], _, _}} = Interpreter.sanitize_code(code)
    end
  end
end
