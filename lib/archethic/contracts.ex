defmodule Archethic.Contracts do
  @moduledoc """
  Handle smart contracts based on a new language running in an custom interpreter for Archethic network.
  Each smart contract is register and supervised as long running process to interact with later on.
  """

  alias __MODULE__.Contract
  alias __MODULE__.ContractConstants, as: Constants
  alias __MODULE__.Interpreter
  alias __MODULE__.Loader
  alias __MODULE__.TransactionLookup
  alias __MODULE__.Worker

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.DateChecker, as: CronDateChecker

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.Contracts.ContractConstants, as: Constants

  require Logger

  @extended_mode? Mix.env() != :prod

  @doc """
  Parse a smart contract code and return a contract struct
  """
  @spec parse(binary()) :: {:ok, Contract.t()} | {:error, binary()}
  defdelegate parse(contract_code),
    to: Interpreter

  @doc """
  Same a `parse/1` but raise if the contract is not valid
  """
  @spec parse!(binary()) :: Contract.t()
  def parse!(contract_code) when is_binary(contract_code) do
    {:ok, contract} = parse(contract_code)
    contract
  end

  @doc """
  Execute a contract retrieved from its address with an incoming transaction
  and validate it according to the smart contract conditions
  """
  @spec execute(binary(), Transaction.t()) :: :ok | {:error, :invalid_condition}
  defdelegate execute(address, tx), to: Worker

  @doc """
  Load transaction into the Smart Contract context leveraging the interpreter
  """
  @spec load_transaction(Transaction.t(), list()) :: :ok
  defdelegate load_transaction(tx, opts), to: Loader

  @spec accept_new_contract?(Transaction.t() | nil, Transaction.t(), DateTime.t()) :: boolean()
  def accept_new_contract?(nil, _, _), do: true
  def accept_new_contract?(%Transaction{data: %TransactionData{code: ""}}, _, _), do: true

  def accept_new_contract?(
        prev_tx = %Transaction{data: %TransactionData{code: code}},
        next_tx = %Transaction{},
        date = %DateTime{}
      ) do
    {:ok,
     %Contract{
       version: version,
       triggers: triggers,
       conditions: conditions
     }} = Interpreter.parse(code)

    with :ok <- validate_conditions(version, conditions, prev_tx, next_tx),
         :ok <- validate_triggers(triggers, next_tx, date) do
      true
    else
      {:error, _} ->
        false
    end
  end

  defp validate_conditions(version, conditions, prev_tx, next_tx) do
    # here we only check that next_tx is allowed based on prev_tx inherit conditions
    case Map.get(conditions, :inherit) do
      nil ->
        :ok

      inherit_conditions ->
        constants = %{
          "previous" => Constants.from_transaction(prev_tx),
          "next" => Constants.from_transaction(next_tx)
        }

        if Interpreter.valid_conditions?(version, inherit_conditions, constants) do
          :ok
        else
          Logger.error("Inherit constraints not respected")
          {:error, :invalid_inherit_constraints}
        end
    end
  end

  defp validate_triggers(triggers, _next_tx, _date) when map_size(triggers) == 0, do: :ok

  defp validate_triggers(triggers, next_tx, date) do
    if Enum.any?(triggers, fn {trigger_type, _} ->
         valid_from_trigger?(trigger_type, next_tx, date)
       end) do
      :ok
    else
      Logger.error("Transaction not processed by a valid smart contract trigger")
      {:error, :invalid_triggers_execution}
    end
  end

  defp valid_from_trigger?(
         {:datetime, datetime},
         %Transaction{},
         validation_date = %DateTime{}
       ) do
    # Accept time drifing for 10seconds
    DateTime.diff(validation_date, datetime) >= 0 and
      DateTime.diff(validation_date, datetime) < 10
  end

  defp valid_from_trigger?(
         {:interval, interval},
         %Transaction{},
         validation_date = %DateTime{}
       ) do
    interval
    |> CronParser.parse!(@extended_mode?)
    |> CronDateChecker.matches_date?(DateTime.to_naive(validation_date))
  end

  defp valid_from_trigger?(_, _, _), do: true

  @doc """
  List the address of the transaction which has contacted a smart contract
  """
  @spec list_contract_transactions(contract_address :: binary()) ::
          list(
            {transaction_address :: binary(), transaction_timestamp :: DateTime.t(),
             protocol_version :: non_neg_integer()}
          )
  defdelegate list_contract_transactions(address),
    to: TransactionLookup,
    as: :list_contract_transactions

  @doc """
  Termine a smart contract execution when a new transaction on the chain happened
  """
  @spec stop_contract(binary()) :: :ok
  defdelegate stop_contract(address), to: Loader
end
