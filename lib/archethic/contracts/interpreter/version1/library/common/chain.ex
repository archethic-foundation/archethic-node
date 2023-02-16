defmodule Archethic.Contracts.Interpreter.Version1.Library.Common.Chain do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Version1.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Version0

  @spec fetch_genesis_address(binary()) :: binary()
  defdelegate fetch_genesis_address(address),
    to: Version0.Library,
    as: :get_genesis_address

  @spec fetch_first_transaction_address(binary()) :: binary()
  defdelegate fetch_first_transaction_address(address),
    to: Version0.Library,
    as: :get_first_transaction_address

  @spec fetch_genesis_public_key(binary()) :: binary()
  defdelegate fetch_genesis_public_key(public_key),
    to: Version0.Library,
    as: :get_genesis_public_key

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:fetch_genesis_address, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:fetch_first_transaction_address, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:fetch_genesis_public_key, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
