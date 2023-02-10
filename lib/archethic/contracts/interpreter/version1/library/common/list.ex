defmodule Archethic.Contracts.Interpreter.Version1.Library.Common.List do
  @moduledoc false
  defdelegate take_element_at_index(list, idx), to: Enum, as: :at

  # TODO: check types of arguments

  # check_types(:take_element_at_index, 0): AST.is_variable/1 or AST.is_list/1
  # check_types(:take_element_at_index, 1): AST.is_variable/1 or AST.is_integer/1
end
