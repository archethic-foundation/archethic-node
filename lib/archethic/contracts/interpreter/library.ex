defmodule Archethic.Contracts.Interpreter.Library do
  @moduledoc false

  @doc """
  Check the types of given parameters for the given function.
  This is AST manipulation.
  We cannot check everything (variable or return of fn), but we can at least forbid what's really wrong.
  """
  @callback check_types(atom(), list(Macro.t())) :: boolean()

  defmodule Error do
    defexception [:message]
  end

  @doc """
  Validate a module function call with arity
  """
  @spec validate_module_call(
          module_name :: binary(),
          function_name :: binary(),
          arity :: non_neg_integer()
        ) ::
          :ok
          | {:error, :module_not_exists | :function_not_exists | :invalid_function_arity,
             error_message :: binary()}
  def validate_module_call(module_name, function_name, arity) do
    with {:ok, module} <- get_module(module_name),
         module_functions = get_module_functions_as_string(module),
         {:ok, matched_functions} <- validate_function_exists(module_functions, function_name),
         :ok <- validate_function_arity(matched_functions, arity) do
      :ok
    else
      {:error, reason} ->
        error_message = get_error_message(reason, module_name, function_name, arity)
        {:error, reason, error_message}
    end
  end

  @doc """
  Return a module fomr a given module_name.
  Raise a no match error of module doesn't exist
  """
  @spec get_module!(module_name :: binary()) :: module()
  def get_module!(module_name) do
    {:ok, module} = get_module(module_name)
    module
  end

  @doc """
  Return true if function is tagged with a specific tag, false otherwise
  Raise an error if module or function does not exist
  """
  @spec function_tagged_with?(module_name :: binary(), function_name :: binary(), tag :: atom()) ::
          boolean()
  def function_tagged_with?(module_name, function_name, tag) do
    module_impl = get_module_impl!(module_name)
    function = String.to_existing_atom(function_name)
    module_impl.tagged_with?(function, tag)
  rescue
    _ -> false
  end

  defp get_module(module_name) do
    module =
      "Elixir.Archethic.Contracts.Interpreter.Library.Common.#{module_name}"
      |> String.to_existing_atom()
      |> Code.ensure_loaded!()

    {:ok, module}
  rescue
    _ -> {:error, :module_not_exists}
  end

  defp get_module_impl!(module_name) do
    module = get_module!(module_name)

    try do
      %Knigge.Options{default: module_impl} = Knigge.options!(module)
      module_impl
    rescue
      _ -> module
    end
  end

  defp get_module_functions_as_string(module) do
    module.__info__(:functions)
    |> Enum.map(fn {name, arity} ->
      {Atom.to_string(name), arity}
    end)
  end

  defp validate_function_exists(module_functions, function_name) do
    case Enum.filter(module_functions, &(elem(&1, 0) == function_name)) do
      [] -> {:error, :function_not_exists}
      functions -> {:ok, functions}
    end
  end

  defp validate_function_arity(functions, arity) do
    if Enum.any?(functions, &(elem(&1, 1) == arity)) do
      :ok
    else
      {:error, :invalid_function_arity}
    end
  end

  defp get_error_message(:module_not_exists, module_name, _, _),
    do: "Module #{module_name} does not exists"

  defp get_error_message(:function_not_exists, module_name, function_name, _),
    do: "Function #{module_name}.#{function_name} does not exists"

  defp get_error_message(:invalid_function_arity, module_name, function_name, arity),
    do: "Function #{module_name}.#{function_name} does not exists with #{arity} arguments"
end
