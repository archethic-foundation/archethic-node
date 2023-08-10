defmodule Archethic.Contracts.Interpreter.Library.Common.Code do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Tag
  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  use Tag

  @spec is_same?(binary(), binary()) :: boolean()
  def is_same?(first_code, second_code) do
    first_ast = first_code |> Interpreter.sanitize_code(ignore_meta?: true)
    second_ast = second_code |> Interpreter.sanitize_code(ignore_meta?: true)

    first_ast == second_ast
  end

  @spec is_valid?(binary()) :: boolean()
  def is_valid?(code) do
    case Interpreter.parse(code) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:is_same?, [first, second]) do
    (AST.is_binary?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:is_valid?, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
