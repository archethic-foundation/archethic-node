defmodule Archethic.Contracts.Interpreter.Version1.Library.Common.List do
  @moduledoc false

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  @spec take_element_at_index(list(), integer()) :: any()
  defdelegate take_element_at_index(list, idx), to: Enum, as: :at

  def check_types(:take_element_at_index, [first, second]) do
    (AST.is_list?(first) || AST.is_variable?(first)) &&
      (AST.is_integer?(second) || AST.is_variable?(second))
  end

  def check_types(_, _), do: false
end
