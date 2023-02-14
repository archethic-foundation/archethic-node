defmodule Archethic.Contracts.Interpreter.Version1.Library.Contract do
  @moduledoc """
  We are delegating to the version 0 transaction statements.
  This is fine as long as we don't need to change anything.
  If there's something to change for version 1, do the change in here, not in version 0.
  """

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.TransactionChain.Transaction
  alias Archethic.Contracts.Interpreter.Version0.TransactionStatements

  @spec set_type(Transaction.t(), binary()) :: Transaction.t()
  defdelegate set_type(tx, type), to: TransactionStatements

  @spec set_content(Transaction.t(), binary() | integer() | float()) :: Transaction.t()
  defdelegate set_content(tx, content), to: TransactionStatements

  @spec set_code(Transaction.t(), binary()) :: Transaction.t()
  defdelegate set_code(tx, args), to: TransactionStatements

  @spec add_recipient(Transaction.t(), binary()) :: Transaction.t()
  defdelegate add_recipient(tx, args), to: TransactionStatements

  @spec add_recipients(Transaction.t(), list(binary())) :: Transaction.t()
  defdelegate add_recipients(tx, args), to: TransactionStatements

  @spec add_uco_transfer(Transaction.t(), map()) :: Transaction.t()
  def add_uco_transfer(tx, args) do
    TransactionStatements.add_uco_transfer(tx, :proplists.from_map(args))
  end

  @spec add_uco_transfers(Transaction.t(), list(map())) :: Transaction.t()
  def add_uco_transfers(tx, args) do
    casted_args = Enum.map(args, &:proplists.from_map/1)
    TransactionStatements.add_uco_transfers(tx, casted_args)
  end

  @spec add_token_transfer(Transaction.t(), map()) :: Transaction.t()
  def add_token_transfer(tx, args) do
    TransactionStatements.add_token_transfer(tx, :proplists.from_map(args))
  end

  @spec add_token_transfers(Transaction.t(), list(map())) :: Transaction.t()
  def add_token_transfers(tx, args) do
    casted_args = Enum.map(args, &:proplists.from_map/1)
    TransactionStatements.add_token_transfers(tx, casted_args)
  end

  @spec add_ownership(Transaction.t(), map()) :: Transaction.t()
  def add_ownership(tx, args) do
    TransactionStatements.add_ownership(tx, :proplists.from_map(args))
  end

  @spec add_ownerships(Transaction.t(), list(map())) :: Transaction.t()
  def add_ownerships(tx, args) do
    casted_args = Enum.map(args, &:proplists.from_map/1)
    TransactionStatements.add_ownerships(tx, casted_args)
  end

  @doc """
  Check the types of given parameters for the given function.
  This is AST manipulation.
  We cannot check everything, but we can at least forbid what's really wrong.

  We do not need to check the transaction argument because _we_ are feeding it
  """
  @spec check_types(atom(), list()) :: boolean()
  def check_types(:set_type, [first]) do
    AST.is_variable?(first) ||
      Transaction.types()
      |> Enum.map(&Atom.to_string/1)
      |> Enum.member?(first)
  end

  def check_types(:set_content, [first]) do
    AST.is_binary?(first) || AST.is_integer?(first) || AST.is_float?(first) ||
      AST.is_variable?(first)
  end

  def check_types(:add_uco_transfer, [first]) do
    AST.is_map?(first) || AST.is_variable?(first)
  end

  def check_types(:add_token_transfer, [first]) do
    AST.is_map?(first) || AST.is_variable?(first)
  end

  def check_types(:set_code, [first]) do
    AST.is_binary?(first) || AST.is_variable?(first)
  end

  def check_types(:add_ownership, [first]) do
    AST.is_map?(first) || AST.is_variable?(first)
  end

  def check_types(:add_recipient, [first]) do
    AST.is_binary?(first) || AST.is_variable?(first)
  end

  def check_types(:add_recipients, [first]) do
    AST.is_list?(first) || AST.is_variable?(first)
  end

  def check_types(:add_ownerships, [first]) do
    AST.is_list?(first) || AST.is_variable?(first)
  end

  def check_types(:add_token_transfers, [first]) do
    AST.is_list?(first) || AST.is_variable?(first)
  end

  def check_types(:add_uco_transfers, [first]) do
    AST.is_list?(first) || AST.is_variable?(first)
  end

  def check_types(_, _), do: false
end
