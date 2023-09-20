defmodule Archethic.Contracts.Interpreter.Library.Common.Chain do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Crypto

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Library.Common.ChainImpl

  use Knigge, otp_app: :archethic, default: ChainImpl, delegate_at_runtime?: true

  @callback get_genesis_address(binary()) :: Crypto.prepended_hash()
  @callback get_first_transaction_address(binary()) :: Crypto.prepended_hash() | nil
  @callback get_genesis_public_key(binary()) :: Crypto.key() | nil
  @callback get_transaction(binary()) :: map()
  @callback get_burn_address() :: Crypto.prepended_hash()
  @callback get_previous_address(Crypto.key() | map()) :: Crypto.prepended_hash()
  @callback get_balance(Crypto.prepended_hash()) :: map()
  @callback get_uco_balance(Crypto.prepended_hash()) :: float()

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:get_genesis_address, [first]) do
    binary_or_variable_or_function?(first)
  end

  def check_types(:get_first_transaction_address, [first]) do
    binary_or_variable_or_function?(first)
  end

  def check_types(:get_genesis_public_key, [first]) do
    binary_or_variable_or_function?(first)
  end

  def check_types(:get_transaction, [first]) do
    binary_or_variable_or_function?(first)
  end

  def check_types(:get_burn_address, []), do: true

  def check_types(:get_previous_address, [first]) do
    AST.is_map?(first) || binary_or_variable_or_function?(first)
  end

  def check_types(:get_balance, [first]) do
    binary_or_variable_or_function?(first)
  end

  def check_types(:get_uco_balance, [first]) do
    binary_or_variable_or_function?(first)
  end

  def check_types(_, _), do: false

  defp binary_or_variable_or_function?(arg) do
    AST.is_binary?(arg) || AST.is_variable_or_function_call?(arg)
  end
end
