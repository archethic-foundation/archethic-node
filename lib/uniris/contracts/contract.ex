defmodule Uniris.Contracts.Contract do
  @moduledoc """
  Represents a smart contract
  """

  alias Uniris.Contracts.Contract.Conditions
  alias Uniris.Contracts.Contract.Constants
  alias Uniris.Contracts.Contract.Triggers
  alias Uniris.Contracts.Interpreter

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  defstruct triggers: %Triggers{},
            conditions: %Conditions{},
            actions: {:__block__, [], []},
            constants: %Constants{}

  @type t :: %__MODULE__{
          triggers: Triggers.t(),
          conditions: Conditions.t(),
          actions: Macro.t(),
          constants: Constants.t()
        }

  @doc """
  Parse the code part from the transaction data to a build a contract representation and load the transaction details as constants
  """
  @spec from_transaction!(Transaction.t()) :: t()
  def from_transaction!(tx = %Transaction{data: %TransactionData{code: code}}) do
    {:ok, ast} = Interpreter.parse(code)
    from_ast(ast, tx)
  end

  @doc """
  Build a contract from the AST representation
  """
  @spec from_ast(Macro.t()) :: t()
  def from_ast(_ast = {:actions, _, [[do: actions]]}) do
    %__MODULE__{actions: actions}
  end

  def from_ast(ast = {:__block__, [], _elems}) do
    reduce_blocks(%__MODULE__{}, ast)
  end

  @doc """
  Build a contract from the AST representation and load the transaction details as constants
  """
  @spec from_ast(Macro.t(), Transaction.t()) :: t()
  def from_ast(_ast = {:actions, _, [[do: actions]]}, tx = %Transaction{}) do
    %__MODULE__{
      actions: actions,
      constants: Constants.from_transaction(tx)
    }
  end

  def from_ast(ast = {:__block__, [], _elems}, tx = %Transaction{}) do
    %__MODULE__{constants: Constants.from_transaction(tx)}
    |> reduce_blocks(ast)
  end

  defp reduce_blocks(contract, _ast = {:__block__, [], elems}) do
    Enum.reduce(elems, contract, &do_build_contract(&1, &2))
  end

  defp do_build_contract({:trigger, _, [triggers]}, contract = %__MODULE__{}) do
    Enum.reduce(triggers, contract, fn {token, value}, acc ->
      {token, value} = format_token(token, value)
      Map.update(acc, :triggers, %{token => value}, &Map.put(&1, token, value))
    end)
  end

  defp do_build_contract({:condition, _, [conditions]}, contract = %__MODULE__{}) do
    Enum.reduce(conditions, contract, fn {token, value}, acc ->
      {token, value} = format_token(token, value)
      Map.update(acc, :conditions, %{token => value}, &Map.put(&1, token, value))
    end)
  end

  defp do_build_contract(
         {:actions, _, [[do: {:__block__, _, _} = actions]]},
         contract = %__MODULE__{}
       ) do
    %{contract | actions: actions}
  end

  defp do_build_contract({:actions, _, [[do: elems]]}, contract = %__MODULE__{}) do
    %{contract | actions: elems}
  end

  defp format_token(:datetime, timestamp), do: {:datetime, DateTime.from_unix!(timestamp)}
  defp format_token(:interval, interval), do: {:interval, interval}
  defp format_token(:origin_family, {:biometric, _, _}), do: {:origin_family, :biometric}
  defp format_token(:origin_family, {:software, _, _}), do: {:origin_family, :software}
  defp format_token(:origin_family, {:usb, _, _}), do: {:origin_family, :usb}
  defp format_token(token, value), do: {token, value}
end
