defmodule Archethic.Contracts.Interpreter.Scope do
  @moduledoc """
  Helper functions to deal with scopes
  """

  @doc """
  Initialize the scope with given map
  """
  @spec init(map()) :: :ok
  def init(global_variables \\ %{}) do
    Process.put(
      :scope,
      global_variables
    )

    :ok
  end

  @doc """
  Create a new nested scope
  """
  @spec create(list(String.t())) :: :ok
  def create(scope_hierarchy) do
    Process.put(
      :scope,
      put_in(Process.get(:scope), scope_hierarchy, %{})
    )

    :ok
  end

  @doc """
  Write the variable in the most relevant scope (cascade to all parent)
  Fallback to current scope if variable doesn't exist anywhere
  """
  @spec write_cascade(list(String.t()), String.t(), any()) :: :ok
  def write_cascade(scope_hierarchy, var_name, value) do
    Process.put(
      :scope,
      put_in(
        Process.get(:scope),
        where_is(scope_hierarchy, var_name) ++ [var_name],
        value
      )
    )

    :ok
  end

  @doc """
  Write the variable at given scope
  """
  @spec write_at(list(String.t()), String.t(), any()) :: :ok
  def write_at(scope_hierarchy, var_name, value) do
    Process.put(
      :scope,
      put_in(
        Process.get(:scope),
        scope_hierarchy ++ [var_name],
        value
      )
    )

    :ok
  end

  @doc """
  Update the global variable (or prop) at path with given function
  """
  @spec update_global(list(String.t()), (any() -> any())) :: :ok
  def update_global(path, update_fn) do
    Process.put(
      :scope,
      update_in(
        Process.get(:scope),
        path,
        update_fn
      )
    )

    :ok
  end

  @doc """
  Read the global variable (or prop) at path
  """
  @spec read_global(list(String.t())) :: any()
  def read_global(path) do
    get_in(
      Process.get(:scope),
      path
    )
  end

  @doc """
  Read the variable starting at given scope and cascading until the root
  """
  @spec read(list(String.t()), String.t()) :: any()
  def read(scopes_hierarchy, var_name) do
    get_in(
      Process.get(:scope),
      where_is(scopes_hierarchy, var_name) ++ [var_name]
    )
  end

  @doc """
  Read the map's property starting at given scope and cascading until the root
  """
  @spec read(list(String.t()), String.t(), String.t()) :: any()
  def read(scopes_hierarchy, map_name, key_name) do
    get_in(
      Process.get(:scope),
      where_is(scopes_hierarchy, map_name) ++ [map_name, key_name]
    )
  end

  def get_function_ast(function_name, nil) do
    function_key = function_name <> "/" <> "0"
    get_in(Process.get(:scope), [:functions, function_key, :ast])
  end

  def get_function_ast(function_name, args) do
    function_key = function_name <> "/" <> Integer.to_string(length(args))
    get_in(Process.get(:scope), [:functions, function_key, :ast])
  end

  def execute_function_ast(function_name, args) do
      get_function_ast(function_name, args)
      |> Code.eval_quoted()
      |> elem(0)
  end

  # Return the path where to assign/read a variable.
  # It will recurse from the deepest path to the root path until it finds a match.
  # If no match it will return the current path.
  defp where_is(current_path, variable_name) do
    do_where_is(current_path, variable_name, current_path)
  end

  defp do_where_is(current_path, variable_name, []) do
    # there are magic variables at the root of scope (contract/transaction/next/previous)
    case get_in(Process.get(:scope), [variable_name]) do
      nil ->
        current_path

      _ ->
        []
    end
  end

  defp do_where_is(current_path, variable_name, acc) do
    case get_in(Process.get(:scope), acc ++ [variable_name]) do
      nil ->
        do_where_is(current_path, variable_name, List.delete_at(acc, -1))

      _ ->
        acc
    end
  end
end
