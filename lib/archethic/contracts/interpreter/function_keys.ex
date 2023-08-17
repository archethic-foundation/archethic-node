defmodule Archethic.Contracts.Interpreter.FunctionKeys do
  @moduledoc """
  This module is a helper module to manage function keys (name, arity, visibility)
  """

  @type t() :: %{
          {name :: binary(), arity :: non_neg_integer()} => :public | :private
        }

  @spec new() :: t()
  def new(), do: Map.new()

  @spec add_private(keys :: t(), function_name :: binary(), arity :: non_neg_integer()) :: t()
  def add_private(keys, function_name, arity), do: Map.put(keys, {function_name, arity}, :private)

  @spec add_public(keys :: t(), function_name :: binary(), arity :: non_neg_integer()) :: t()
  def add_public(keys, function_name, arity), do: Map.put(keys, {function_name, arity}, :public)

  @spec exist?(keys :: t(), name :: binary(), arity :: non_neg_integer()) :: boolean()
  def exist?(keys, name, arity), do: Map.has_key?(keys, {name, arity})

  @spec private?(keys :: t(), name :: binary(), arity :: non_neg_integer()) :: boolean()
  def private?(keys, name, arity), do: Map.fetch!(keys, {name, arity}) == :private
end
