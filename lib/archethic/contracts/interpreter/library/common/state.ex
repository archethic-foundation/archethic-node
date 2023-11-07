defmodule Archethic.Contracts.Interpreter.Library.Common.State do
  @moduledoc false

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Scope
  alias Archethic.Tag

  use Tag

  @behaviour Library

  @spec get(String.t()) :: any()
  def get(key) do
    unless is_binary(key) do
      raise(Library.Error, message: "State.get/1 `key` must be a string")
    end

    get(key, nil)
  end

  @spec get(String.t(), any()) :: any()
  def get(key, default) do
    unless is_binary(key) do
      raise(Library.Error, message: "State.get/2 `key` must be a string")
    end

    case Scope.read_global([:state, key]) do
      nil -> default
      value -> value
    end
  end

  @tag [:write_state]
  @spec set(String.t(), any()) :: nil
  def set(key, value) do
    unless is_binary(key) do
      raise(Library.Error, message: "State.set/2 `key` must be a string")
    end

    Scope.update_global([:state, key], fn _ -> value end)
    nil
  end

  @spec delete(String.t()) :: nil
  def delete(key) do
    unless is_binary(key) do
      raise(Library.Error, message: "State.delete/1 `key` must be a string")
    end

    Scope.update_global([:state], fn state -> Map.delete(state, key) end)
    nil
  end

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:get, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:get, [first, _second]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:set, [first, _second]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:delete, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
