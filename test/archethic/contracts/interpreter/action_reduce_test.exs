defmodule Archethic.Contracts.Interpreter.ActionReduceTest do
  @moduledoc """
  Here we test the content of a reduce.

  Everything related to the outside world (outside variables, library functions etc.) is tested in action_text.exs
  """
  use ArchethicCase

  alias Archethic.Contracts.ActionInterpreter
  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.ActionReduce
  alias Archethic.Contracts.Interpreter.Utils

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
               |> parse()
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
               |> parse()
    end

    test "should parse a dot access" do
      code = """
      reduce [1,2,3], as: item, with: [count: 0] do
        count = count + item * transaction.an_integer
      end
      """

      assert {:ok, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> parse()
    end

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
               |> parse()
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
               |> parse()
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
               |> parse()
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
               |> parse()
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
               |> parse()
    end
  end

  describe "execute/2" do
    test "should be able to use 1 acc variable" do
      code = """
      reduce [1,2,3], as: item, with: [count: 0] do
        count = count + item
      end
      """

      assert %{"count" => 6} = sanitize_parse_execute(code)
    end

    test "should be able to use multiple acc variable" do
      code = """
      reduce [1,2,3], as: item, with: [sum: 0, product: 1] do
        sum = sum + item
        product = product * item
      end
      """

      assert %{"sum" => 6, "product" => 6} = sanitize_parse_execute(code)
    end

    test "should be able to use new variable" do
      code = """
      reduce [1,2,3], as: item, with: [count: 0] do
        other = 10
        count = count + item + other
      end
      """

      assert %{"count" => 36} = sanitize_parse_execute(code)
    end

    test "should be able to use keywords" do
      code = """
      reduce [1,2,3], as: item, with: [count: 0] do
        keyword = [value: item]
        count = count + keyword.value
      end
      """

      assert %{"count" => 6} = sanitize_parse_execute(code)
    end

    test "should be able to use library functions" do
      code = """
      reduce [1,2,3], as: item, with: [count: 0] do
        if in?(item, [2,4,6]) do
          count = count + 1
        end
      end
      """

      assert %{"count" => 1} = sanitize_parse_execute(code)
    end
  end

  # --------------------
  # helper functions
  # --------------------
  defp sanitize_parse_execute(code, constants \\ %{}) do
    ast =
      code
      |> Interpreter.sanitize_code()
      |> elem(1)
      |> parse()
      |> elem(1)

    bindings =
      []
      |> ActionInterpreter.add_scope_binding(constants)
      |> ActionReduce.add_scope_binding()

    case Code.eval_quoted(ast, bindings) do
      {result, _bindings} ->
        result
    end
  end

  defp parse(ast) do
    case Macro.traverse(
           ast,
           ActionReduce.initial_acc(),
           &ActionReduce.prewalk/2,
           &ActionReduce.postwalk/2
         ) do
      {node, _} ->
        {:ok, node}
    end
  catch
    {:error, reason, node} ->
      {:error, Utils.format_error_reason(node, reason)}

    {:error, node} ->
      # IO.inspect(node, label: "err")
      {:error, Utils.format_error_reason(node, "unexpected term")}
  end
end
