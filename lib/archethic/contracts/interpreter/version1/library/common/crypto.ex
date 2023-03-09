defmodule Archethic.Contracts.Interpreter.Version1.Library.Common.Crypto do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Version1.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Legacy

  @spec hash(binary(), binary()) :: binary()
  defdelegate hash(content, algo \\ "sha256"),
    to: Legacy.Library,
    as: :hash

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:hash, [first, second]) do
    (AST.is_binary?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:hash, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
