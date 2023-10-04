defmodule Archethic.Contracts.Interpreter.Library.Common.Chain do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Library.Common.ChainImpl

  use Knigge, otp_app: :archethic, default: ChainImpl, delegate_at_runtime?: true

  @callback get_genesis_address(binary()) :: binary()
  @callback get_first_transaction_address(binary()) :: binary() | nil
  @callback get_last_address(binary()) :: binary()
  @callback get_genesis_public_key(binary()) :: binary() | nil
  @callback get_transaction(binary()) :: map() | nil
  @callback get_last_transaction(binary()) :: map() | nil
  @callback get_burn_address() :: binary()
  @callback get_previous_address(binary() | map()) :: binary()
  @callback get_balance(binary()) :: map()
  @callback get_uco_balance(binary()) :: float()
  @callback get_token_balance(binary(), binary()) :: float()
  @callback get_token_balance(binary(), binary(), non_neg_integer()) :: float()
  @callback get_tokens_balance(binary()) :: list()
  @callback get_tokens_balance(binary(), list()) :: list()

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:get_genesis_address, [first]) do
    binary_or_variable_or_function?(first)
  end

  def check_types(:get_first_transaction_address, [first]) do
    binary_or_variable_or_function?(first)
  end

  def check_types(:get_last_address, [first]) do
    binary_or_variable_or_function?(first)
  end

  def check_types(:get_genesis_public_key, [first]) do
    binary_or_variable_or_function?(first)
  end

  def check_types(:get_transaction, [first]) do
    binary_or_variable_or_function?(first)
  end

  def check_types(:get_last_transaction, [first]) do
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

  def check_types(:get_token_balance, [first, second]) do
    binary_or_variable_or_function?(first) && binary_or_variable_or_function?(second)
  end

  def check_types(:get_token_balance, [first, second, third]) do
    check_types(:get_token_balance, [first, second]) && number_or_variable_or_function?(third)
  end

  def check_types(:get_tokens_balance, [first]) do
    binary_or_variable_or_function?(first)
  end

  def check_types(:get_tokens_balance, [first, second]) do
    check_types(:get_tokens_balance, [first]) && list_or_variable_or_function?(second)
  end

  def check_types(_, _), do: false

  defp binary_or_variable_or_function?(arg) do
    AST.is_binary?(arg) || AST.is_variable_or_function_call?(arg)
  end

  defp number_or_variable_or_function?(arg) do
    AST.is_number?(arg) || AST.is_variable_or_function_call?(arg)
  end

  defp list_or_variable_or_function?(arg) do
    AST.is_list?(arg) || AST.is_variable_or_function_call?(arg)
  end
end
