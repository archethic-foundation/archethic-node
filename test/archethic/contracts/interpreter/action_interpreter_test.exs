defmodule Archethic.Contracts.Interpreter.ActionInterpreterTest do
  use ArchethicCase
  use ExUnitProperties

  import ArchethicCase

  alias Archethic.Contracts.ContractConstants, as: Constants
  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.ActionInterpreter

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer

  doctest ActionInterpreter

  # ----------------------------------------------
  # parse/1
  # ----------------------------------------------
  describe "parse/1" do
    test "should not be able to parse when there is a non-whitelisted module" do
      code = ~S"""
      actions triggered_by: transaction do
        String.to_atom "hello"
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to use whitelisted module existing function" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content "hello"
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to have comments" do
      code = ~S"""
      actions triggered_by: transaction do
        # this is a comment
        "hello contract"
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should return the correct trigger type" do
      code = ~S"""
      actions triggered_by: oracle do
      end
      """

      assert {:ok, :oracle, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])

      code = ~S"""
      actions triggered_by: interval, at: "* * * * *"  do
      end
      """

      assert {:ok, {:interval, "* * * * *"}, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])

      code = ~S"""
      actions triggered_by: datetime, at: 1676282760 do
      end
      """

      assert {:ok, {:datetime, ~U[2023-02-13 10:06:00Z]}, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should not parse if datetime is not rounded" do
      code = ~S"""
      actions triggered_by: datetime, at: 1687164224 do
      end
      """

      assert {:error, _, "Datetime triggers must be rounded to the minute"} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should return a proper error message if trigger is invalid" do
      code = ~S"""
      actions triggered_by: datetime do
      end
      """

      assert {:error, _, "Invalid trigger"} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should not be able to use whitelisted module non existing function" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.non_existing_fn()
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])

      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content("hello", "hola")
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to create variables" do
      code = ~S"""
      actions triggered_by: transaction do
        content = "hello"
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to create lists" do
      code = ~S"""
      actions triggered_by: transaction do
        list = [1,2,3]
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to create keywords" do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2, three: 3]
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to use common functions" do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [1,2,3]
        List.at(numbers, 1)
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should not be able to use non existing functions" do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [1,2,3]
        List.at(numbers, 1, 2, 3)
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])

      code = ~S"""
      actions triggered_by: transaction do
        numbers = [1,2,3]
        List.non_existing_function()
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should not be able to use wrong types in common functions" do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [1,2,3]
        List.at(1, numbers)
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to use the result of a function call as a parameter" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content Json.to_string([1,2,3])
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to use a function call as a parameter to a lib function" do
      code = ~S"""
      actions triggered_by: transaction do
        list = [1,2,3,4,5]
        count = List.size(List.append(list, 6))
        Contract.set_content(count)
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should not be able to use wrong types in contract functions" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content [1,2,3]
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should not be able to use if as an expression" do
      code = ~S"""
      actions triggered_by: transaction do
        var = if true do
          "foo"
        else
          "bar"
        end
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should not be able to use for as an expression" do
      code = ~S"""
      actions triggered_by: transaction do
        var = for i in [1,2] do
          i
        end
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to use nested ." do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2, three: 3]
        var = [numbers: numbers]

        Contract.set_content var.numbers.one
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])

      code = ~S"""
      actions triggered_by: transaction do
        a = [b: [c: [d: [e: [f: [g: [h: "hello"]]]]]]]

        Contract.set_content a.b.c.d.e.f.g.h
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to use [] access with a string" do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2, three: 3]

        Contract.set_content numbers["one"]
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to use [] access with a variable" do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2, three: 3]
        x = "one"

        Contract.set_content numbers[x]
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to use [] access with a dot access" do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2, three: 3]
        x = [value: "one"]

        Contract.set_content numbers[x.value]
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to use [] access with a fn call" do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = ["1": 1, two: 2, three: 3]

        Contract.set_content numbers[String.from_number 1]
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to use nested [] access" do
      code = ~S"""
      actions triggered_by: transaction do
        a = [b: [c: [d: [e: [f: [g: [h: "hello"]]]]]]]

        Contract.set_content a["b"]["c"]["d"]["e"]["f"]["g"]["h"]
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to use loop" do
      code = ~S"""
      actions triggered_by: transaction do
        result = 0

        for i in [1,2,3] do
            result = result + i
        end

        Contract.set_content result
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to use ranges" do
      code = ~S"""
      actions triggered_by: transaction do
        range = 1..10
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should not be able to use non existing function" do
      code = ~S"""
      actions triggered_by: transaction do
        hello()
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to use existing function" do
      code = ~S"""
      actions triggered_by: transaction do
        hello()
      end
      """

      # public function
      assert {:ok, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               # mark as existing
               |> ActionInterpreter.parse([{"hello", 0, :public}])

      # private function
      assert {:ok, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               # mark as existing
               |> ActionInterpreter.parse([{"hello", 0, :private}])
    end

    test "should be able to use named action without argument" do
      code = ~S"""
      actions triggered_by: transaction, on: upgrade do
        Contract.set_code transaction.content
      end
      """

      assert {:ok, {:transaction, "upgrade", []}, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end

    test "should be able to use named action with arguments" do
      code = ~S"""
      actions triggered_by: transaction, on: vote(candidate) do
        Contract.set_content "..."
      end
      """

      assert {:ok, {:transaction, "vote", ["candidate"]}, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])

      code = ~S"""
      actions triggered_by: transaction, on: count(x, y) do
        Contract.set_content "..."
      end
      """

      assert {:ok, {:transaction, "count", ["x", "y"]}, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse([])
    end
  end

  # ----------------------------------------------
  # execute/2
  # ----------------------------------------------

  describe "execute/2" do
    test "should be able to call the Contract module" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content "hello"
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)
    end

    test "should be able to change the contract even if there are code after" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content "hello"
        some = "code"
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)
    end

    test "should be able to use a variable" do
      code = ~S"""
      actions triggered_by: transaction do
        content = "hello"
        Contract.set_content content
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)
    end

    test "should be able to use a function call as parameter" do
      code = ~S"""
      actions triggered_by: transaction do
        content = "hello"
        Contract.set_content Json.to_string(content)
      end
      """

      assert %Transaction{data: %TransactionData{content: "\"hello\""}} =
               sanitize_parse_execute(code)
    end

    test "should be able to use a keyword as a map" do
      code = ~S"""
      actions triggered_by: transaction do
        content = [text: "hello"]
        Contract.set_content content.text
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)
    end

    test "should be able to use a common module" do
      code = ~S"""
      actions triggered_by: transaction do
        content = [1,2,3]
        two = List.at(content, 1)
        Contract.set_content two
      end
      """

      assert %Transaction{data: %TransactionData{content: "2"}} = sanitize_parse_execute(code)
    end

    test "should evaluate actions based on if statement" do
      code = ~S"""
      actions triggered_by: transaction do
        if true do
          Contract.set_content "yes"
        else
          Contract.set_content "no"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "yes"}} = sanitize_parse_execute(code)
    end

    test "should consider the ! (not) keyword" do
      code = ~S"""
      actions triggered_by: transaction do
        if !false do
          Contract.set_content "yes"
        else
          Contract.set_content "no"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "yes"}} = sanitize_parse_execute(code)
    end

    test "should not parse if trying to access an undefined variable" do
      code = ~S"""
      actions triggered_by: transaction do
        if true do
          content = "hello"
        end
        Contract.set_content content
      end
      """

      # TODO: we want a parsing error not a runtime error
      assert_raise FunctionClauseError, fn ->
        sanitize_parse_execute(code)
      end
    end

    test "should be able to access a parent scope variable" do
      code = ~S"""
      actions triggered_by: transaction do
        content = "hello"
        if true do
          Contract.set_content content
        else
          Contract.set_content "should not happen"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        content = "hello"
        if true do
          Contract.set_content "#{content} world"
        else
          Contract.set_content "should not happen"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello world"}} =
               sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        content = "hello"
        if true do
          if true do
            Contract.set_content content
          end
        else
          Contract.set_content "should not happen"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)
    end

    test "should be able to have variable in block" do
      code = ~S"""
      actions triggered_by: transaction do
        if true do
          content = "hello"
          Contract.set_content content
        else
          Contract.set_content "should not happen"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        if true do
          content = "hello"
          Contract.set_content "#{content} world"
        else
          Contract.set_content "should not happen"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello world"}} =
               sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        if true do
          content = "hello"
          if true do
            Contract.set_content content
          end
        else
          Contract.set_content "should not happen"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)
    end

    test "should be able to update a parent scope variable" do
      code = ~S"""
      actions triggered_by: transaction do
        content = ""

        if true do
          content = "hello"
        end

        Contract.set_content content
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        content = ""

        if false do
          content = "hello"
        end

        Contract.set_content content
      end
      """

      assert %Transaction{data: %TransactionData{content: ""}} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        content = ""

        if false do
          content = "should not happen"
        else
          content = "hello"
        end

        Contract.set_content content
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        content = ""

        if true do
          content = "layer 1"
          if true do
            content = "layer 2"
            if true do
              content = "layer 3"
            end
          end
        end

        Contract.set_content content
      end
      """

      assert %Transaction{data: %TransactionData{content: "layer 3"}} =
               sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        content = ""

        if true do
          if true do
            if true do
              content = "layer 3"
            end
          end
        end

        Contract.set_content content
      end
      """

      assert %Transaction{data: %TransactionData{content: "layer 3"}} =
               sanitize_parse_execute(code)
    end

    test "should be able to use nested ." do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2, three: 3]
        var = [numbers: numbers]

        Contract.set_content var.numbers.one
      end
      """

      assert %Transaction{data: %TransactionData{content: "1"}} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        a = [b: [c: [d: [e: [f: [g: [h: "hello"]]]]]]]

        Contract.set_content a.b.c.d.e.f.g.h
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do

        if true do
          a = [b: [c: [d: [e: [f: [g: [h: "hello"]]]]]]]
          if true do
            Contract.set_content a.b.c.d.e.f.g.h
          end
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)
    end

    test "should be able to use for loop" do
      code = ~S"""
      actions triggered_by: transaction do
        result = 0

        for var in [1,2,3] do
            result = result + var
        end

        Contract.set_content result
      end
      """

      assert %Transaction{data: %TransactionData{content: "6"}} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        result = 0
        list = [1,2,3]

        for num in list do
            result = result + num
        end

        Contract.set_content result
      end
      """

      assert %Transaction{data: %TransactionData{content: "6"}} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        result = 0

        for num in [1,2,3] do
            y = num
            result = result + num + y
        end

        Contract.set_content result
      end
      """

      assert %Transaction{data: %TransactionData{content: "12"}} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        for num in [1,2,3] do
          if num == 2 do
            Contract.set_content "ok"
          end
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end

    test "should be able to use ranges" do
      code = ~S"""
      actions triggered_by: transaction do
        text = ""
        for num in 1..4 do
          text = "#{text}#{num}\n"
        end
        Contract.set_content text
      end
      """

      assert %Transaction{data: %TransactionData{content: "1\n2\n3\n4\n"}} =
               sanitize_parse_execute(code)
    end

    test "should be able to use [] access with a string" do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2, three: 3]

        Contract.set_content numbers["one"]
      end
      """

      assert %Transaction{data: %TransactionData{content: "1"}} = sanitize_parse_execute(code)
    end

    test "should be able to use [] access with a variable" do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2, three: 3]
        x = "one"

        Contract.set_content numbers[x]
      end
      """

      assert %Transaction{data: %TransactionData{content: "1"}} = sanitize_parse_execute(code)
    end

    test "should be able to use [] access with a dot access" do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2, three: 3]
        x = [value: "one"]

        Contract.set_content numbers[x.value]
      end
      """

      assert %Transaction{data: %TransactionData{content: "1"}} = sanitize_parse_execute(code)
    end

    test "should be able to use [] access with a fn call" do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = ["1": 1, two: 2, three: 3]

        Contract.set_content numbers[String.from_number 1]
      end
      """

      assert %Transaction{data: %TransactionData{content: "1"}} = sanitize_parse_execute(code)
    end

    test "should be able to use nested [] access" do
      code = ~S"""
      actions triggered_by: transaction do
        a = [b: [c: [d: [e: [f: [g: [h: "hello"]]]]]]]
        d = "d"

        Contract.set_content a["b"]["c"][d]["e"]["f"]["g"]["h"]
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)
    end
  end

  describe "BigInt" do
    test "wrote in transfers" do
      address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      address2 = <<0::16, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        a = 5
        b = 5.1
        c = 15
        Contract.add_uco_transfer to: "#{Base.encode16(address)}", amount: a
        Contract.add_uco_transfer to: "#{Base.encode16(address2)}", amount: b
        Contract.add_token_transfer([to: "#{Base.encode16(address)}", amount: c, token_id: 1, token_address: "#{Base.encode16(address2)}"])
      end
      """

      expected_a = Archethic.Utils.to_bigint(5)
      expected_b = Archethic.Utils.to_bigint(5.1)
      expected_c = Archethic.Utils.to_bigint(15)

      assert %Transaction{
               data: %TransactionData{
                 ledger: %Ledger{
                   token: %TokenLedger{
                     transfers: [
                       %TokenTransfer{
                         to: ^address,
                         amount: ^expected_c,
                         token_address: ^address2,
                         token_id: 1
                       }
                     ]
                   },
                   uco: %UCOLedger{
                     transfers: [
                       %UCOTransfer{to: ^address2, amount: ^expected_b},
                       %UCOTransfer{to: ^address, amount: ^expected_a}
                     ]
                   }
                 }
               }
             } = sanitize_parse_execute(code)
    end

    test "read from transfers" do
      address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      address2 = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      token_address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      address_hex = Base.encode16(address)
      address2_hex = Base.encode16(address2)

      code = ~s"""
      actions triggered_by: transaction do
        if transaction.uco_transfers["#{address_hex}"] == 2 do
          if List.at(transaction.token_transfers["#{address2_hex}"], 0).amount == 3.12345 do
            Contract.set_content "ok"
          end
        end
      end
      """

      tx = %Transaction{
        data: %TransactionData{
          ledger: %Ledger{
            token: %TokenLedger{
              transfers: [
                %TokenTransfer{
                  to: address2,
                  amount: Archethic.Utils.to_bigint(3.12345),
                  token_address: token_address,
                  token_id: 1
                }
              ]
            },
            uco: %UCOLedger{
              transfers: [
                %UCOTransfer{to: address, amount: Archethic.Utils.to_bigint(2)}
              ]
            }
          }
        }
      }

      # FIXME: keys of transfers are binaries (should be hex), why?

      assert %Transaction{data: %TransactionData{content: "ok"}} =
               sanitize_parse_execute(code, %{
                 "transaction" => Constants.from_transaction(tx)
               })
    end

    test "should keep the code by default" do
      code = ~s"""
      actions triggered_by: transaction do
        Contract.set_content("exotic crow")
      end
      """

      assert %Transaction{data: %TransactionData{code: ^code}} = sanitize_parse_execute(code)
    end

    test "should be able to clear the code" do
      code = ~s"""
      actions triggered_by: transaction do
        Contract.set_code("")
      end
      """

      assert %Transaction{data: %TransactionData{code: ""}} = sanitize_parse_execute(code)
    end

    test "maths are OK" do
      code = ~s"""
      actions triggered_by: transaction do
        # this is a known rounding issue in elixir
        a = 0.1 * 0.1
        if a == 0.01 do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)

      code = ~s"""
      actions triggered_by: transaction do
        a = 0.145 * 2
        if a == 0.29 do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)

      code = ~s"""
      actions triggered_by: transaction do
        a = 1 / 3
        if a == 0.33333333 do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)

      code = ~s"""
      actions triggered_by: transaction do
        a = 2 / 3
        if a == 0.66666666 do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)

      code = ~s"""
      actions triggered_by: transaction do
        a = 0.29 + 0.15
        if a == 0.44 do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)

      code = ~s"""
      actions triggered_by: transaction do
        a = 12 / 2
        if a == 6 do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)

      code = ~s"""
      actions triggered_by: transaction do
        a = 12 + 120
        if a == 132 do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)

      code = ~s"""
      actions triggered_by: transaction do
        a = 1 - 120
        if a == -119 do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)

      code = ~s"""
      actions triggered_by: transaction do
        a = 0.1 + 0.2
        if a == 0.3 do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end

    property "floating points additions" do
      check all(
              lhs <- StreamData.float(),
              rhs <- StreamData.float()
            ) do
        code = ~s"""
        actions triggered_by: transaction do
          Contract.set_content (#{lhs} + #{rhs})
        end
        """

        assert %Transaction{data: %TransactionData{content: content}} =
                 sanitize_parse_execute(code)

        assert_less_than_8_decimals(content)
      end
    end

    property "floating points multiplication" do
      check all(
              lhs <- StreamData.float(),
              rhs <- StreamData.float()
            ) do
        code = ~s"""
        actions triggered_by: transaction do
          Contract.set_content (#{lhs} * #{rhs})
        end
        """

        assert %Transaction{data: %TransactionData{content: content}} =
                 sanitize_parse_execute(code)

        assert_less_than_8_decimals(content)
      end
    end

    property "floating points division" do
      check all(
              lhs <- StreamData.float(),
              rhs <-
                StreamData.float()
                |> StreamData.filter(&(&1 != 0.0))
            ) do
        code = ~s"""
        actions triggered_by: transaction do
          Contract.set_content (#{lhs} / #{rhs})
        end
        """

        assert %Transaction{data: %TransactionData{content: content}} =
                 sanitize_parse_execute(code)

        assert_less_than_8_decimals(content)
      end
    end

    property "floating points substraction" do
      check all(
              lhs <- StreamData.float(),
              rhs <- StreamData.float()
            ) do
        code = ~s"""
        actions triggered_by: transaction do
          Contract.set_content (#{lhs} - #{rhs})
        end
        """

        assert %Transaction{data: %TransactionData{content: content}} =
                 sanitize_parse_execute(code)

        assert_less_than_8_decimals(content)
      end
    end
  end

  defp assert_less_than_8_decimals(str) do
    assert (case(String.split(str, ".")) do
              [_] ->
                true

              [_real, decimals] ->
                String.length(decimals) <= 8
            end)
  end
end
