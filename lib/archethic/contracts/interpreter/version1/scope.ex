defmodule Archethic.Contracts.Interpreter.Version1.Scope do
  @moduledoc """
  Helper functions to deal with scope
  """

  @doc """
  Return the path where to assign a variable.
  It will recurse from the deepest path to the root path until it finds a match.
  If no match it will return the current path.
  """
  @spec where_to_assign_variable(map(), list(reference()), binary()) :: list(reference())
  def where_to_assign_variable(scope, current_path, variable_name) do
    do_where_to_assign_variable(scope, current_path, variable_name, current_path)
  end

  defp do_where_to_assign_variable(scope, current_path, variable_name, []) do
    # there are magic variables at the root of scope (contract/transaction)
    case get_in(scope, [variable_name]) do
      nil ->
        current_path

      _ ->
        []
    end
  end

  defp do_where_to_assign_variable(scope, current_path, variable_name, acc) do
    case get_in(scope, acc ++ [variable_name]) do
      nil ->
        do_where_to_assign_variable(scope, current_path, variable_name, List.delete_at(acc, -1))

      _ ->
        acc
    end
  end
end
