defmodule Archethic.Contracts.Interpreter.ActionReduceTest do
  use ArchethicCase

  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.ActionReduce

  describe "parse/1" do
    test "should parse if list is a variable" do
      code = """
      reduce list, [as: item, with: [count: 0]] do
        count = count + item
      end
      """

      assert {:ok, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionReduce.parse()
    end

    test "should parse a list" do
      code = """
      reduce [1,2,3], as: item, with: [count: 0] do
        count = count + item
      end
      """

      assert {:ok, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionReduce.parse()
    end

    # test "should parse a function" do
    # # Impossible right now because I need to whitelist a function
    #   code = """
    #   reduce get_calls(), as: item, with: [count: 0] do
    #     count = count + item
    #   end
    #   """

    #   assert {:ok, _} =
    #            code
    #            |> Interpreter.sanitize_code()
    #            |> elem(1)
    #            |> ActionReduce.parse()
    # end

    test "should not parse nested reduce" do
      code = """
      reduce [], as: i, with: [acc0: 0] do
        reduce [], as: j, with: [acc1: 1] do
          acc1 = 1
        end
      end
      """

      assert {:error, "Nested reduce are forbidden - reduce - L2"} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionReduce.parse()
    end

    test "should not parse if rebinding the as" do
      code = """
      reduce [], as: item, with: [count: 0] do
        item = item
        count = count + item
      end
      """

      assert {:error, "Rebinding the \"item\" variable is forbidden - N/A - L2"} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionReduce.parse()
    end

    test "should not parse if first argument is invalid" do
      code = """
      reduce 1, as: item, with: [count: 0] do
        count = count + item
      end
      """

      assert {:error, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionReduce.parse()
    end

    test "should not parse if second argument is invalid" do
      code = """
      reduce [], as: 42, with: [count: 0] do
        count = count + item
      end
      """

      assert {:error, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionReduce.parse()
    end

    test "should not parse if third argument is invalid" do
      code = """
      reduce [], as: i, with: acc do
        count = count + item
      end
      """

      assert {:error, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionReduce.parse()
    end

    # test "should parse a with value is a variable" do
    #   # might be impossible at the moment cause it's in parent scope
    #   code = """
    #   initial_count = 0
    #   reduce list, as: item, with: [count: initial_count] do
    #     count = count + item
    #   end
    #   """

    #   assert {:ok, _} =
    #            code
    #            |> Interpreter.sanitize_code()
    #            |> elem(1)
    #            |> ActionReduce.parse()
    # end
  end

  describe "execute/2" do
    test "should be able to use 1 acc variable" do
      code = """
      reduce [1,2,3], as: item, with: [count: 0] do
        count = count + item
      end
      """

      assert %{"count" => 6} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionReduce.parse()
               |> elem(1)
               |> ActionReduce.execute()
    end

    test "should be able to use multiple acc variable" do
      code = """
      reduce [1,2,3], as: item, with: [sum: 0, product: 1] do
        sum = sum + item
        product = product * item
      end
      """

      assert %{"sum" => 6, "product" => 6} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionReduce.parse()
               |> elem(1)
               |> ActionReduce.execute()
    end

    test "should be able to use new variable" do
      code = """
      reduce [1,2,3], as: item, with: [count: 0] do
        other = 10
        count = count + item + other
      end
      """

      assert %{"count" => 36} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionReduce.parse()
               |> elem(1)
               |> ActionReduce.execute()
    end

    # access scope parent
    # access contract/transaction
  end
end
