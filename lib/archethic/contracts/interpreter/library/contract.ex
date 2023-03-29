defmodule Archethic.Contracts.Interpreter.Library.Contract do
  @moduledoc """
  We are delegating to the legacy transaction statements.
  This is fine as long as we don't need to change anything.
  If there's something to change for version 1, do the change in here, not in legacy.
  """
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.TransactionChain.Transaction
  alias Archethic.Contracts.Interpreter.Legacy.TransactionStatements

  # get_calls has it's own postwalk (to inject the address),
  # it does not require a check_types
  @spec get_calls(binary()) :: list(map())
  def get_calls(contract_address) do
    # FIXME TODO
    []
  end

  @spec set_type(Transaction.t(), binary()) :: Transaction.t()
  defdelegate set_type(next_tx, type),
    to: TransactionStatements

  @spec set_content(Transaction.t(), binary() | integer() | float()) :: Transaction.t()
  defdelegate set_content(next_tx, content),
    to: TransactionStatements

  @spec set_code(Transaction.t(), binary()) :: Transaction.t()
  defdelegate set_code(next_tx, args),
    to: TransactionStatements

  @spec add_recipient(Transaction.t(), binary()) :: Transaction.t()
  defdelegate add_recipient(next_tx, args),
    to: TransactionStatements

  @spec add_recipients(Transaction.t(), list(binary())) :: Transaction.t()
  defdelegate add_recipients(next_tx, args),
    to: TransactionStatements

  @spec add_uco_transfer(Transaction.t(), map()) :: Transaction.t()
  def add_uco_transfer(next_tx, args) do
    TransactionStatements.add_uco_transfer(next_tx, Map.to_list(args))
  end

  @spec add_uco_transfers(Transaction.t(), list(map())) :: Transaction.t()
  def add_uco_transfers(next_tx, args) do
    casted_args = Enum.map(args, &Map.to_list/1)
    TransactionStatements.add_uco_transfers(next_tx, casted_args)
  end

  @spec add_token_transfer(Transaction.t(), map()) :: Transaction.t()
  def add_token_transfer(next_tx, args) do
    TransactionStatements.add_token_transfer(next_tx, Map.to_list(args))
  end

  @spec add_token_transfers(Transaction.t(), list(map())) :: Transaction.t()
  def add_token_transfers(next_tx, args) do
    casted_args = Enum.map(args, &Map.to_list/1)
    TransactionStatements.add_token_transfers(next_tx, casted_args)
  end

  @spec add_ownership(Transaction.t(), map()) :: Transaction.t()
  def add_ownership(next_tx, args) do
    TransactionStatements.add_ownership(next_tx, Map.to_list(args))
  end

  @spec add_ownerships(Transaction.t(), list(map())) :: Transaction.t()
  def add_ownerships(next_tx, args) do
    casted_args = Enum.map(args, &Map.to_list/1)
    TransactionStatements.add_ownerships(next_tx, casted_args)
  end

  # We do not need to check the transaction argument because _we_ are feeding it (after this step)
  @spec check_types(atom(), list()) :: boolean()
  def check_types(:set_type, [first]) do
    AST.is_variable_or_function_call?(first) ||
      Transaction.types()
      |> Enum.map(&Atom.to_string/1)
      |> Enum.member?(first)
  end

  def check_types(:set_content, [first]) do
    AST.is_binary?(first) || AST.is_integer?(first) || AST.is_float?(first) ||
      AST.is_variable_or_function_call?(first)
  end

  def check_types(:add_uco_transfer, [first]) do
    AST.is_map?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:add_token_transfer, [first]) do
    AST.is_map?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:set_code, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:add_ownership, [first]) do
    AST.is_map?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:add_recipient, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:add_recipients, [first]) do
    AST.is_list?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:add_ownerships, [first]) do
    AST.is_list?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:add_token_transfers, [first]) do
    AST.is_list?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:add_uco_transfers, [first]) do
    AST.is_list?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
