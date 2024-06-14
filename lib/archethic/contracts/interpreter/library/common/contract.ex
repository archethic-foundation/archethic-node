defmodule Archethic.Contracts.Interpreter.Library.Common.Contract do
  @moduledoc """
  We are delegating to the legacy transaction statements.
  This is fine as long as we don't need to change anything.
  If there's something to change for version 1, do the change in here, not in legacy.
  """
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Legacy.UtilsInterpreter
  alias Archethic.Contracts.Interpreter.Legacy.TransactionStatements

  alias Archethic.Tag

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData.Recipient

  alias Archethic.Utils

  use Tag

  # we do not use knigge because we do not mock the entire module
  @contract_impl Application.compile_env(
                   :archethic,
                   __MODULE__,
                   Archethic.Contracts.Interpreter.Library.Common.ContractImpl
                 )

  @tag [:write_contract]
  @spec set_type(Transaction.t(), binary()) :: Transaction.t()
  defdelegate set_type(next_tx, type),
    to: TransactionStatements

  @tag [:write_contract]
  @spec set_content(Transaction.t(), binary() | Decimal.t() | integer()) :: Transaction.t()
  def set_content(next_tx, content) when is_binary(content) do
    put_in(next_tx, [Access.key(:data), Access.key(:content)], content)
  end

  def set_content(next_tx, int) when is_integer(int) do
    put_in(
      next_tx,
      [Access.key(:data), Access.key(:content)],
      Integer.to_string(int)
    )
  end

  def set_content(next_tx, decimal = %Decimal{}) do
    put_in(
      next_tx,
      [Access.key(:data), Access.key(:content)],
      case Utils.maybe_decimal_to_integer(decimal) do
        int when is_integer(int) ->
          Integer.to_string(int)

        _ ->
          Decimal.to_string(decimal, :normal)
      end
    )
  end

  @tag [:write_contract]
  @spec set_code(Transaction.t(), binary()) :: Transaction.t()
  defdelegate set_code(next_tx, args),
    to: TransactionStatements

  @tag [:write_contract]
  @spec add_recipient(Transaction.t(), binary() | map()) :: Transaction.t()
  def add_recipient(next_tx = %Transaction{}, address) when is_binary(address) do
    add_recipient(next_tx, %{
      "address" => address,
      "action" => nil,
      "args" => nil
    })
  end

  def add_recipient(next_tx = %Transaction{}, %{
        "address" => recipient_address,
        "action" => action,
        "args" => args
      })
      when is_binary(recipient_address) and
             (is_binary(action) or is_nil(action)) and
             (is_list(args) or is_nil(args)) do
    recipient_address = UtilsInterpreter.get_address(recipient_address, :add_recipient)

    recipient = %Recipient{
      address: recipient_address,
      action: action,
      args: args
    }

    update_in(
      next_tx,
      [Access.key(:data), Access.key(:recipients)],
      &[recipient | &1]
    )
  end

  def add_recipient(_, _), do: raise("invalid recipient")

  @tag [:write_contract]
  @spec add_recipients(Transaction.t(), list(binary())) :: Transaction.t()
  def add_recipients(next_tx = %Transaction{}, args) when is_list(args) do
    Enum.reduce(args, next_tx, &add_recipient(&2, &1))
  end

  @tag [:write_contract]
  @spec add_uco_transfer(Transaction.t(), map()) :: Transaction.t()
  def add_uco_transfer(next_tx, args) do
    args =
      Map.update!(args, "amount", fn amount ->
        Decimal.new(amount) |> Decimal.mult(100_000_000) |> Decimal.to_integer()
      end)

    TransactionStatements.add_uco_transfer(next_tx, Map.to_list(args))
  end

  @tag [:write_contract]
  @spec add_uco_transfers(Transaction.t(), list(map())) :: Transaction.t()
  def add_uco_transfers(next_tx, args) do
    Enum.reduce(args, next_tx, &add_uco_transfer(&2, &1))
  end

  @tag [:write_contract]
  @spec add_token_transfer(Transaction.t(), map()) :: Transaction.t()
  def add_token_transfer(next_tx, args) do
    # FIXME: handle more decimals
    args =
      args
      |> Map.update!("amount", fn amount ->
        Decimal.new(amount) |> Decimal.mult(100_000_000) |> Decimal.to_integer()
      end)

    TransactionStatements.add_token_transfer(next_tx, Map.to_list(args))
  end

  @tag [:write_contract]
  @spec add_token_transfers(Transaction.t(), list(map())) :: Transaction.t()
  def add_token_transfers(next_tx, args) do
    Enum.reduce(args, next_tx, &add_token_transfer(&2, &1))
  end

  @tag [:write_contract]
  @spec add_ownership(Transaction.t(), map()) :: Transaction.t()
  def add_ownership(next_tx, args) do
    TransactionStatements.add_ownership(next_tx, Map.to_list(args))
  end

  @tag [:write_contract]
  @spec add_ownerships(Transaction.t(), list(map())) :: Transaction.t()
  def add_ownerships(next_tx, args) do
    casted_args = Enum.map(args, &Map.to_list/1)
    TransactionStatements.add_ownerships(next_tx, casted_args)
  end

  @tag [:io]
  @spec call_function(address :: binary(), function :: binary(), args :: list()) :: any()
  def call_function(address, function, args) do
    # for some reason I failed to use defdelegate
    apply(@contract_impl, :call_function, [address, function, args])
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
    AST.is_binary?(first) || AST.is_number?(first) ||
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
    AST.is_binary?(first) || AST.is_map?(first) || AST.is_variable_or_function_call?(first)
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

  def check_types(:call_function, [first, second, third]) do
    (AST.is_binary?(first) || AST.is_variable_or_function_call?(first)) and
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second)) and
      (AST.is_list?(third) || AST.is_variable_or_function_call?(third))
  end

  def check_types(_, _), do: false
end
