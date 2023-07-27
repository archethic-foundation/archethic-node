defmodule Archethic.Contracts.Interpreter.Scope do
  @moduledoc """
  Helper functions to deal with scopes
  """

  @doc """
  Initialize the scope with given map
  """
  @spec init(map()) :: :ok
  def init(global_variables \\ %{}) do
    global_variables = Map.put(global_variables, "context_list", [])

    Process.put(
      :scope,
      global_variables
    )

    :ok
  end

  @doc """
  Create a new nested scope
  """
  @spec create() :: :ok
  def create() do
    current_context = get_current_context()
    current_scope_hierarchy = get_context_scope_hierarchy(current_context)
    ref = new_ref()

    Process.put(
      :scope,
      put_in(Process.get(:scope), [current_context] ++ current_scope_hierarchy ++ [ref], %{})
    )

    Process.put(
      :scope,
      update_in(Process.get(:scope), [current_context, "scope_hierarchy"], &(&1 ++ [ref]))
    )

    :ok
  end

  @doc """
  Create new context
  """
  @spec create_context() :: :ok
  def create_context() do
    context_ref = new_ref()

    new_context = %{
      "scope_hierarchy" => []
    }

    # add context to scope and update context list
    new_scope =
      Process.get(:scope)
      |> Map.put(context_ref, new_context)
      |> Map.update!("context_list", &[context_ref | &1])

    Process.put(:scope, new_scope)

    :ok
  end

  @doc """
  Leave a scope by removing it from current context's scope hierarchy and deleting its content
  """
  @spec leave_scope() :: :ok
  def leave_scope() do
    current_context = get_current_context()

    Process.put(
      :scope,
      update_in(
        Process.get(:scope),
        [current_context, "scope_hierarchy"],
        &List.delete_at(&1, -1)
      )
    )

    :ok
  end

  @doc """
  Leave a context by removing it from scope and context_list
  """
  @spec leave_context() :: :ok
  def leave_context() do
    current_context = get_current_context()

    new_scope =
      Process.get(:scope)
      |> Map.delete(current_context)
      |> Map.update!("context_list", &List.delete_at(&1, 0))

    Process.put(:scope, new_scope)

    :ok
  end

  @doc """
  Execute ast after creating specific context for it and return execution's result
  """
  @spec execute(any(), map()) :: :ok
  def execute(ast, constants) do
    init(constants)
    create_context()
    {result, _} = Code.eval_quoted(ast)
    leave_context()
    result
  end

  @doc """
  Write the variable in the most relevant scope (cascade to all parent)
  Fallback to current scope if variable doesn't exist anywhere
  """
  @spec write_cascade(String.t(), any()) :: :ok
  def write_cascade(var_name, value) do
    current_context = get_current_context()
    context_scope_hierarchy = get_context_scope_hierarchy(current_context)

    Process.put(
      :scope,
      put_in(
        Process.get(:scope),
        where_is(current_context, context_scope_hierarchy, var_name) ++ [var_name],
        value
      )
    )

    :ok
  end

  @doc """
  Write the variable at given context's scope
  """
  @spec write_at(String.t(), any()) :: :ok
  def write_at(var_name, value) do
    current_context = get_current_context()
    current_scope_hierarchy = get_context_scope_hierarchy(current_context)

    Process.put(
      :scope,
      put_in(
        Process.get(:scope),
        [current_context] ++ current_scope_hierarchy ++ [var_name],
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
  Read the variable from current context's scope
  and cascading until the global scope (avoiding context's root)
  """
  @spec read(String.t()) :: any()
  def read(var_name) do
    current_context = get_current_context()
    scope_hierarchy = get_context_scope_hierarchy(current_context)

    get_in(
      Process.get(:scope),
      where_is(current_context, scope_hierarchy, var_name) ++ [var_name]
    )
  end

  @doc """
  Read the map's property starting at given context's scope and cascading until the root
  """
  @spec read(String.t(), String.t()) :: any()
  def read(map_name, key_name) do
    current_context = get_current_context()
    current_scope_hierarchy = get_context_scope_hierarchy(current_context)

    get_in(
      Process.get(:scope),
      where_is(current_context, current_scope_hierarchy, map_name) ++ [map_name, key_name]
    )
  end

  defp get_current_context() do
    get_in(Process.get(:scope), ["context_list"])
    |> List.first()
  end

  defp get_context_scope_hierarchy(context) do
    get_in(Process.get(:scope), [context, "scope_hierarchy"])
  end

  defp new_ref() do
    :erlang.list_to_binary(:erlang.ref_to_list(make_ref()))
  end

  defp get_function_ast(function_name, args) do
    get_in(Process.get(:scope), ["functions", {function_name, length(args)}, :ast])
  end

  @doc """
  Execute a function AST
  """
  @spec execute_function_ast(String.t(), list(any())) :: any()
  def execute_function_ast(function_name, args) do
    create_context()

    result =
      get_function_ast(function_name, args)
      |> Code.eval_quoted()
      |> elem(0)

    leave_context()
    result
  end

  # Return the path where to assign/read a variable.
  # It will recurse from the deepest path to the root path until it finds a match.
  # If no match it will return the current path.
  defp where_is(context, current_path, variable_name) do
    case do_where_is(context, variable_name, current_path) do
      nil -> [context] ++ current_path
      path -> path
    end
  end

  defp do_where_is(_context, variable_name, []) do
    # there are magic variables at the root of scope (contract/transaction/next/previous)
    case get_in(Process.get(:scope), [variable_name]) do
      nil -> nil
      _ -> []
    end
  end

  defp do_where_is(context, variable_name, acc) do
    case get_in(Process.get(:scope), [context] ++ acc ++ [variable_name]) do
      nil -> do_where_is(context, variable_name, List.delete_at(acc, -1))
      _ -> [context] ++ acc
    end
  end
end
