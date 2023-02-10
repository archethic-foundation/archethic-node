defmodule Archethic.Contracts.Interpreter.Version1.Library do
  @moduledoc false

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

  defp get_module_functions_as_string(module) do
    module.__info__(:functions)
    |> Enum.map(fn {name, arity} ->
      {Atom.to_string(name), arity}
    end)
  end
end
