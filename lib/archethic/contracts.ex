defmodule Archethic.Contracts do
  @moduledoc """
  Handle smart contracts based on a new language running in an custom interpreter for Archethic network.
  Each smart contract is register and supervised as long running process to interact with later on.
  """

  alias __MODULE__.Contract
  alias __MODULE__.ContractConditions, as: Conditions
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
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient

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
          nil | Recipient.t(),
          Keyword.t()
        ) ::
          {:ok, nil | Transaction.t()}
          | {:error, :contract_failure | :invalid_triggers_execution}
  defdelegate execute_trigger(
                trigger_type,
                contract,
                maybe_trigger_tx,
                maybe_recipient,
                opts \\ []
              ),
              to: Interpreter,
              as: :execute_trigger

  @doc """
  Execute contract's function
  """
  @spec execute_function(
          Contract.t(),
          :string,
          list()
        ) ::
          {:ok, result :: any()}
          | {:error, :function_failure}
          | {:error, :function_does_not_exist}
          | {:error, :function_is_private}
          | {:error, :timeout}

  def execute_function(contract, function_name, args) do
    with {:ok, function} <- get_function_from_contract(contract, function_name, args),
         constants <- get_function_constants_from_contract(contract) do
      task =
        Task.Supervisor.async_nolink(Archethic.TaskSupervisor, fn ->
          Interpreter.execute_function(function, constants, args)
        end)

      # 500ms to execute or raise
      case Task.yield(task, 500) || Task.shutdown(task) do
        {:ok, reply} ->
          {:ok, reply}

        nil ->
          {:error, :timeout}

        {:exit, _reason} ->
          # error from the code (ex: 1 + "abc")
          {:error, :function_failure}
      end
    end
  end

  defp get_function_from_contract(%{functions: functions}, function_name, args) do
    case Map.get(functions, {function_name, length(args)}) do
      nil ->
        {:error, :function_does_not_exist}

      function ->
        case function do
          %{visibility: :public} ->
            {:ok, function}

          %{visibility: :private} ->
            {:error, :function_is_private}
        end
    end
  end

  defp get_function_constants_from_contract(%{
         constants: %Constants{contract: contract_constant}
       }) do
    contract_constant
    |> Constants.map_transactions(&Constants.stringify_transaction/1)
    |> Constants.map_transactions(&Constants.cast_transaction_amount_to_float/1)

    %{
      "contract" => contract_constant,
      :time_now => DateTime.utc_now() |> DateTime.to_unix()
    }
  end

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
        prev_tx = %Transaction{data: %TransactionData{code: code}},
        _next_tx = %Transaction{},
        _contract_context = nil
      )
      when code != "" do
    # only contract without triggers (with only conditions) are allowed to NOT have a Contract.Context
    case from_transaction(prev_tx) do
      {:ok, %Contract{triggers: triggers}} when map_size(triggers) == 0 ->
        true

      _ ->
        false
    end
  end

  def valid_execution?(
        prev_tx = %Transaction{address: previous_address},
        _next_tx = %Transaction{type: next_tx_type, data: next_tx_data},
        %Contract.Context{
          trigger: trigger,
          timestamp: timestamp,
          status: status
        }
      ) do
    with {:ok, maybe_trigger_tx} <- validate_trigger(trigger, timestamp, previous_address),
         {:ok, contract} <- from_transaction(prev_tx) do
      case execute_trigger(
             trigger_to_trigger_type(trigger),
             contract,
             maybe_trigger_tx,
             trigger_to_recipient(trigger),
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

  defp trigger_to_recipient({:transaction, _, recipient}), do: recipient
  defp trigger_to_recipient(_), do: nil

  defp trigger_to_trigger_type({:oracle, _}), do: :oracle
  defp trigger_to_trigger_type({:datetime, datetime}), do: {:datetime, datetime}
  defp trigger_to_trigger_type({:interval, cron, _datetime}), do: {:interval, cron}

  defp trigger_to_trigger_type({:transaction, _, recipient = %Recipient{}}) do
    Contract.get_trigger_for_recipient(recipient)
  end

  # In the case of a trigger interval,
  # because of the delay between execution and validation,
  # we override the value returned by library function Time.now()
  defp trigger_to_execute_opts({:interval, _cron, datetime}), do: [time_now: datetime]
  defp trigger_to_execute_opts(_), do: []

  @doc """
  Validate any kind of condition.
  The transaction and datetime depends on the condition.
  """
  @spec valid_condition?(
          Contract.condition_type(),
          Contract.t(),
          Transaction.t(),
          nil | Recipient.t(),
          DateTime.t()
        ) :: boolean()

  def valid_condition?(
        condition_key,
        contract = %Contract{version: version, conditions: conditions},
        transaction = %Transaction{},
        maybe_recipient,
        datetime
      ) do
    case Map.get(conditions, condition_key) do
      nil ->
        # only inherit condition are optional
        condition_key == :inherit

      %Conditions{args: args, subjects: subjects} ->
        named_action_constants = Interpreter.get_named_action_constants(args, maybe_recipient)

        condition_constants =
          get_condition_constants(condition_key, contract, transaction, datetime)

        Interpreter.valid_conditions?(
          version,
          subjects,
          Map.merge(named_action_constants, condition_constants)
        )
    end
  rescue
    _ ->
      false
  end

  defp validate_trigger({:datetime, datetime}, validation_datetime, _contract_address) do
    if within_drift_tolerance?(validation_datetime, datetime) do
      {:ok, nil}
    else
      :invalid_triggers_execution
    end
  end

  defp validate_trigger(
         {:interval, interval, interval_datetime},
         validation_datetime,
         _contract_address
       ) do
    matches_date? =
      interval
      |> CronParser.parse!(@extended_mode?)
      |> CronDateChecker.matches_date?(DateTime.to_naive(interval_datetime))

    if matches_date? && within_drift_tolerance?(validation_datetime, interval_datetime) do
      {:ok, nil}
    else
      :invalid_triggers_execution
    end
  end

  defp validate_trigger(
         {:transaction, address, _recipient},
         _validation_datetime,
         contract_address
       ) do
    storage_nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    case TransactionChain.fetch_transaction(address, storage_nodes) do
      {:ok,
       tx = %Transaction{
         type: trigger_type,
         address: trigger_address,
         validation_stamp: %ValidationStamp{recipients: trigger_resolved_recipients}
       }} ->
        # check that trigger transaction did indeed call this contract
        if contract_address in trigger_resolved_recipients do
          {:ok, tx}
        else
          Logger.error("Contract was wrongly triggered by transaction",
            transaction_address: Base.encode16(trigger_address),
            transaction_type: trigger_type,
            contract: Base.encode16(contract_address)
          )

          :invalid_triggers_execution
        end

      {:error, _} ->
        # todo: it might too strict to say that it's invalid in some cases (timeout)
        :invalid_triggers_execution
    end
  end

  defp validate_trigger({:oracle, address}, _validation_datetime, _contract_address) do
    storage_nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    case TransactionChain.fetch_transaction(address, storage_nodes) do
      {:ok, tx} ->
        {:ok, tx}

      {:error, _} ->
        # todo: it might too strict to say that it's invalid in some cases (timeout)
        :invalid_triggers_execution
    end
  end

  # validation_time: practical date of trigger
  # datetime: theoretical date of trigger
  defp within_drift_tolerance?(validation_datetime, datetime) do
    DateTime.diff(validation_datetime, datetime) >= 0 and
      DateTime.diff(validation_datetime, datetime) < 10
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
         %Contract{
           constants: %Constants{contract: contract_constant},
           functions: functions
         },
         transaction,
         datetime
       ) do
    %{
      "previous" => contract_constant,
      "next" => Constants.from_transaction(transaction),
      :time_now => DateTime.to_unix(datetime),
      :functions => functions
    }
  end

  defp get_condition_constants(
         _,
         %Contract{
           constants: %Constants{contract: contract_constant},
           functions: functions
         },
         transaction,
         datetime
       ) do
    %{
      "transaction" => Constants.from_transaction(transaction),
      "contract" => contract_constant,
      :time_now => DateTime.to_unix(datetime),
      :functions => functions
    }
  end
end
