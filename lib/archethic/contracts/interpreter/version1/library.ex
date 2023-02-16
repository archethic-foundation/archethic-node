defmodule Archethic.Contracts.Interpreter.Version1.Library do
  @moduledoc false

  @doc """
  Check the types of given parameters for the given function.
  This is AST manipulation.
  We cannot check everything (variable or return of fn), but we can at least forbid what's really wrong.
  """
  @callback check_types(atom(), list(Macro.t())) :: boolean()

  @doc """
  Checks if a function with given arity exists in given module
  """
  @spec function_exists?(module(), binary(), integer) :: boolean()
  def function_exists?(module, functionName, arity) do
    arity in :proplists.get_all_values(
      functionName,
      get_module_functions_as_string(module)
    )
  end

  @doc """
  Returns the list of common modules available.

  This function is also used to create the atoms of the modules
  """
  def list_common_modules() do
    [:Map, :List, :Regex, :Json, :Time, :Chain, :Crypto, :Token, :String]
    |> Enum.map(&Atom.to_string/1)
  end

  # ----------------------------------------
  defp get_module_functions_as_string(module) do
    module.__info__(:functions)
    |> Enum.map(fn {name, arity} ->
      {Atom.to_string(name), arity}
    end)
  end
end
