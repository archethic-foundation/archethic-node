defmodule Archethic.Contracts.Interpreter.Library.Common.Chain do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Legacy

  @spec get_genesis_address(binary()) :: binary()
  defdelegate get_genesis_address(address),
    to: Legacy.Library,
    as: :get_genesis_address

  @spec get_first_transaction_address(binary()) :: binary()
  defdelegate get_first_transaction_address(address),
    to: Legacy.Library,
    as: :get_first_transaction_address

  @spec get_genesis_public_key(binary()) :: binary()
  defdelegate get_genesis_public_key(public_key),
    to: Legacy.Library,
    as: :get_genesis_public_key

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:get_genesis_address, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:get_first_transaction_address, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:get_genesis_public_key, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
