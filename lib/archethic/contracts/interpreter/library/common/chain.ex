defmodule Archethic.Contracts.Interpreter.Library.Common.Chain do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Library.Common.ChainImpl

  use Knigge, otp_app: :archethic, default: ChainImpl, delegate_at_runtime?: true

  @callback get_genesis_address(binary()) :: binary()
  @callback get_first_transaction_address(binary()) :: binary()
  @callback get_genesis_public_key(binary()) :: binary()
  @callback get_transaction(binary()) :: map()

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

  def check_types(:get_transaction, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
