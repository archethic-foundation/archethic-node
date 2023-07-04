defmodule Archethic.Contracts.Interpreter.Library.Common.Chain do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  @callback get_genesis_address(binary()) :: binary()
  @callback get_first_transaction_address(binary()) :: binary()
  @callback get_genesis_public_key(binary()) :: binary()

  def get_genesis_address(address), do: impl().get_genesis_address(address)

  def get_first_transaction_address(address), do: impl().get_first_transaction_address(address)

  def get_genesis_public_key(public_key), do: impl().get_genesis_public_key(public_key)

  defp impl,
    do:
      Application.get_env(
        :archethic,
        Archethic.Contracts.Interpreter.Library.Common.Chain,
        Archethic.Contracts.Interpreter.Library.Common.ChainImpl
      )

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
