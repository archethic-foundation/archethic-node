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

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.DateChecker, as: CronDateChecker

  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction

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
  Execute the contract trigger.
  """
  @spec execute_trigger(
          Contract.trigger_type(),
          Contract.t(),
          nil | Transaction.t(),
          [Transaction.t()],
          Keyword.t()
        ) ::
          {:ok, nil | Transaction.t()}
          | {:error, :contract_failure | :invalid_triggers_execution}
  defdelegate execute_trigger(trigger_type, contract, maybe_trigger_tx, calls, opts \\ []),
    to: Interpreter,
    as: :execute_trigger

  @doc """
  Load transaction into the Smart Contract context leveraging the interpreter
  """
  @spec load_transaction(Transaction.t(), list()) :: :ok
  defdelegate load_transaction(tx, opts), to: Loader

  @doc """
  Validate an execution by re-executing the contract & comparing both transactions.
  They should have the same type & data

  ps: this function is called in the Validation Workflow so next_tx.validation_stamp is nil
  """
  def valid_execution?(
        prev_tx = %Transaction{address: previous_address},
        _next_tx = %Transaction{type: next_tx_type, data: next_tx_data},
        %Contract.Context{
          trigger_type: trigger_type,
          trigger: trigger,
          timestamp: timestamp,
          status: status
        }
      ) do
    nodes = Election.chain_storage_nodes(previous_address, P2P.authorized_and_available_nodes())

    with :ok <- validate_trigger(trigger_type, trigger, timestamp),
         {:ok, contract} <- Interpreter.parse_transaction(prev_tx),
         {:ok, calls} <-
           TransactionChain.fetch_contract_calls(previous_address, nodes) do
      case execute_trigger(
             trigger_type,
             contract,
             trigger_to_maybe_trigger_tx(trigger),
             calls,
             trigger_to_execute_opts(trigger)
           ) do
        {:ok, %Transaction{type: expected_type, data: expected_data}} ->
          status == :tx_output &&
            next_tx_type == expected_type &&
            next_tx_data == expected_data

        {:ok, nil} ->
          status == :no_output

        {:error, _} ->
          status == :failure
      end
    else
      _ ->
        false
    end
  rescue
    err ->
      Logger.warn(Exception.format(:error, err, __STACKTRACE__))
      false
  end

  # In the case of a trigger oracle/transaction,
  # we need to fetch the transaction
  defp trigger_to_maybe_trigger_tx({type, address}) when type in [:oracle, :transaction] do
    {:ok, trigger_tx} = Archethic.search_transaction(address)
    trigger_tx
  end

  defp trigger_to_maybe_trigger_tx(_), do: nil

  # In the case of a trigger interval,
  # because of the delay between execution and validation,
  # we override the value returned by library function Time.now()
  defp trigger_to_execute_opts({:interval, datetime}), do: [time_now: datetime]
  defp trigger_to_execute_opts(_), do: []

  @doc """
  Validate any kind of condition.
  The transaction and datetime depends on the condition.
  """
  @spec valid_condition?(
          :oracle | :transaction | :inherit,
          Contract.t(),
          Transaction.t(),
          DateTime.t()
        ) :: boolean()
  def valid_condition?(
        condition_type,
        contract = %Contract{version: version, conditions: conditions},
        transaction = %Transaction{},
        datetime
      ) do
    case Map.get(conditions, condition_type) do
      nil ->
        true

      condition ->
        constants = get_condition_constants(condition_type, contract, transaction, datetime)
        Interpreter.valid_conditions?(version, condition, constants)
    end
  end

  defp validate_trigger({:datetime, datetime}, _trigger, trigger_datetime) do
    if is_within_drift_tolerance(trigger_datetime, datetime) do
      :ok
    else
      :invalid_triggers_execution
    end
  end

  defp validate_trigger({:interval, interval}, {:interval, interval_datetime}, trigger_datetime) do
    matches_date? =
      interval
      |> CronParser.parse!(@extended_mode?)
      |> CronDateChecker.matches_date?(DateTime.to_naive(interval_datetime))

    if matches_date? && is_within_drift_tolerance(trigger_datetime, interval_datetime) do
      :ok
    else
      :invalid_triggers_execution
    end
  end

  defp validate_trigger(:transaction, {:transaction, _address}, _) do
    # maybe check address exist and contain the contract in the recipients?
    :ok
  end

  defp validate_trigger(:oracle, {:oracle, _address}, _) do
    # maybe check that it is the last available oracle?
    :ok
  end

  defp validate_trigger(_, _, _), do: :invalid_triggers_execution

  # trigger_datetime: practical date of trigger
  # datetime: theoretical date of trigger
  defp is_within_drift_tolerance(trigger_datetime, datetime) do
    now = DateTime.utc_now()

    DateTime.diff(trigger_datetime, datetime) >= 0 and
      DateTime.diff(trigger_datetime, datetime) < 10 and
      DateTime.diff(now, trigger_datetime) >= 0 and
      DateTime.diff(now, trigger_datetime) < 10
  end

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

  @doc """
  Returns a contract instance from a transaction
  """
  @spec from_transaction(Transaction.t()) :: {:ok, Contract.t()} | {:error, String.t()}
  defdelegate from_transaction(tx), to: Contract, as: :from_transaction

  defp get_condition_constants(
         :inherit,
         %Contract{constants: %Constants{contract: contract_constant}},
         transaction,
         datetime
       ) do
    %{
      "previous" => contract_constant,
      "next" => Constants.from_transaction(transaction),
      "_time_now" => DateTime.to_unix(datetime)
    }
  end

  defp get_condition_constants(
         _,
         %Contract{constants: %Constants{contract: contract_constant}},
         transaction,
         datetime
       ) do
    %{
      "transaction" => Constants.from_transaction(transaction),
      "contract" => contract_constant,
      "_time_now" => DateTime.to_unix(datetime)
    }
  end
end
