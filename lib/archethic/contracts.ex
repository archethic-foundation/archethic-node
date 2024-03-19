defmodule Archethic.Contracts do
  @moduledoc """
  Handle smart contracts based on a new language running in an custom interpreter for Archethic network.
  Each smart contract is register and supervised as long running process to interact with later on.
  """

  alias __MODULE__.Conditions
  alias __MODULE__.Constants
  alias __MODULE__.Contract
  alias __MODULE__.Contract.ActionWithoutTransaction
  alias __MODULE__.Contract.ActionWithTransaction
  alias __MODULE__.Contract.ConditionRejected
  alias __MODULE__.Contract.Failure
  alias __MODULE__.Contract.State
  alias __MODULE__.Interpreter
  alias __MODULE__.Loader
  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.Utils

  require Logger

  @extended_mode? Mix.env() != :prod

  @doc """
  Return the minimum trigger interval in milliseconds.
  Depends on the env
  """
  @spec minimum_trigger_interval(boolean()) :: pos_integer()
  def minimum_trigger_interval(extended_mode? \\ @extended_mode?) do
    if extended_mode? do
      1_000
    else
      60_000
    end
  end

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
          trigger :: Contract.trigger_type(),
          contract :: Contract.t(),
          maybe_trigger_tx :: nil | Transaction.t(),
          maybe_recipient :: nil | Recipient.t(),
          inputs :: list(UnspentOutput.t()),
          opts :: Keyword.t()
        ) ::
          {:ok, ActionWithTransaction.t() | ActionWithoutTransaction.t()}
          | {:error, Failure.t()}
  def execute_trigger(
        trigger_type,
        contract = %Contract{
          transaction: contract_tx = %Transaction{address: contract_address},
          state: state
        },
        maybe_trigger_tx,
        maybe_recipient,
        inputs,
        opts \\ []
      ) do
    # TODO: trigger_tx & recipient should be transformed into recipient here
    # TODO: rescue should be done in here as well
    # TODO: implement timeout

    opts =
      case Keyword.get(opts, :time_now) do
        # you must use the :time_now opts during the validation workflow
        # because there is no validation_stamp yet
        nil -> Keyword.put(opts, :time_now, time_now(trigger_type, maybe_trigger_tx))
        _ -> opts
      end

    key =
      case maybe_trigger_tx do
        nil ->
          time = Keyword.fetch!(opts, :time_now)
          {:execute_trigger, trigger_type, contract_address, nil, time, inputs_digest(inputs)}

        %Transaction{
          address: trigger_tx_address,
          validation_stamp: %ValidationStamp{timestamp: time}
        } ->
          {:execute_trigger, trigger_type, contract_address, trigger_tx_address, time,
           inputs_digest(inputs)}
      end

    fn ->
      Interpreter.execute_trigger(
        trigger_type,
        contract,
        maybe_trigger_tx,
        maybe_recipient,
        inputs,
        opts
      )
    end
    |> cache_interpreter_execute(key,
      timeout_err_msg: "Trigger's execution timed-out",
      rescue_err: :trigger_failure
    )
    |> cast_trigger_result(state, contract_tx)
  end

  defp time_now({:transaction, _, _}, %Transaction{
         validation_stamp: %ValidationStamp{timestamp: timestamp}
       }) do
    timestamp
  end

  defp time_now(:oracle, %Transaction{
         validation_stamp: %ValidationStamp{timestamp: timestamp}
       }) do
    timestamp
  end

  defp time_now({:datetime, timestamp}, nil) do
    timestamp
  end

  defp time_now({:interval, interval}, nil) do
    Utils.get_current_time_for_interval(interval)
  end

  defp cast_trigger_result(res = {:ok, _, next_state, logs}, prev_state, contract_tx) do
    if State.empty?(next_state) do
      cast_valid_trigger_result(res, prev_state, contract_tx, nil)
    else
      encoded_state = State.serialize(next_state)

      if State.valid_size?(encoded_state) do
        cast_valid_trigger_result(res, prev_state, contract_tx, encoded_state)
      else
        {:error,
         %Failure{
           logs: logs,
           error: "Execution was successful but the state exceed the threshold",
           stacktrace: [],
           user_friendly_error: "Execution was successful but the state exceed the threshold"
         }}
      end
    end
  end

  defp cast_trigger_result(err = {:error, %Failure{}}, _, _), do: err

  defp cast_trigger_result({:error, err}, _, _) do
    {:error, %Failure{logs: [], error: err, stacktrace: [], user_friendly_error: err}}
  end

  defp cast_trigger_result({:error, err, stacktrace, logs}, _, _) do
    {:error,
     %Failure{
       logs: logs,
       error: err,
       stacktrace: stacktrace,
       user_friendly_error: append_line_to_error(err, stacktrace)
     }}
  end

  # No output transaction, no state update
  defp cast_valid_trigger_result({:ok, nil, next_state, logs}, previous_state, _, encoded_state)
       when next_state == previous_state do
    {:ok, %ActionWithoutTransaction{encoded_state: encoded_state, logs: logs}}
  end

  # No output transaction but state update
  defp cast_valid_trigger_result({:ok, nil, _next_state, logs}, _, contract_tx, encoded_state) do
    {:ok,
     %ActionWithTransaction{
       encoded_state: encoded_state,
       logs: logs,
       next_tx: generate_next_tx(contract_tx)
     }}
  end

  defp cast_valid_trigger_result({:ok, next_tx, _next_state, logs}, _, _, encoded_state) do
    {:ok, %ActionWithTransaction{encoded_state: encoded_state, logs: logs, next_tx: next_tx}}
  end

  @doc """
  Execute contract's function
  """
  @spec execute_function(
          contract :: Contract.t(),
          function_name :: String.t(),
          args_values :: list(),
          inputs :: list(UnspentOutput.t())
        ) ::
          {:ok, value :: any(), logs :: list(String.t())}
          | {:error, Failure.t()}
  def execute_function(
        contract = %Contract{
          transaction: contract_tx,
          version: contract_version,
          state: state
        },
        function_name,
        args_values,
        inputs
      ) do
    case get_function_from_contract(contract, function_name, args_values) do
      {:error, :function_does_not_exist} ->
        {:error,
         %Failure{
           user_friendly_error: "The function you are trying to call does not exist",
           error: :function_does_not_exist
         }}

      {:error, :function_is_private} ->
        {:error,
         %Failure{
           user_friendly_error: "The function you are trying to call is private",
           error: :function_is_private
         }}

      {:ok, function} ->
        contract_constants =
          contract_tx
          |> Constants.from_transaction(contract_version)
          |> Constants.set_balance(inputs)

        constants = %{
          "contract" => contract_constants,
          :time_now => DateTime.utc_now() |> DateTime.to_unix(),
          :encrypted_seed => Contract.get_encrypted_seed(contract),
          :state => state
        }

        task =
          Task.Supervisor.async_nolink(Archethic.TaskSupervisor, fn ->
            try do
              # TODO: logs
              logs = []
              value = Interpreter.execute_function(function, constants, args_values)
              {:ok, value, logs}
            rescue
              err ->
                # error from the code (ex: 1 + "abc")
                {:error, err, __STACKTRACE__}
            end
          end)

        # 500ms to execute or raise
        case Task.yield(task, 500) || Task.shutdown(task) do
          nil ->
            {:error,
             %Failure{
               user_friendly_error: "Function's execution timed-out",
               error: :function_timeout
             }}

          {:ok, {:error, err, stacktrace}} ->
            {:error,
             %Failure{
               user_friendly_error: append_line_to_error(err, stacktrace),
               error: :function_failure,
               stacktrace: stacktrace,
               logs: []
             }}

          {:ok, {:ok, value, logs}} ->
            {:ok, value, logs}
        end
    end
  end

  defp get_function_from_contract(%{functions: functions}, function_name, args_values) do
    case Map.get(functions, {function_name, length(args_values)}) do
      nil ->
        {:error, :function_does_not_exist}

      function ->
        case function do
          %{visibility: :public} -> {:ok, function}
          %{visibility: :private} -> {:error, :function_is_private}
        end
    end
  end

  @doc """
  Load transaction into the Smart Contract context leveraging the interpreter
  """
  @spec load_transaction(
          tx :: Transaction.t(),
          genesis_address :: Crypto.prepended_hash(),
          opts :: Keyword.t()
        ) :: :ok
  defdelegate load_transaction(tx, genesis_address, opts), to: Loader

  @doc """
  Validate any kind of condition.
  The transaction and datetime depends on the condition.
  """
  @spec execute_condition(
          condition_type :: Contract.condition_type(),
          contract :: Contract.t(),
          incoming_transaction :: Transaction.t(),
          maybe_recipient :: nil | Recipient.t(),
          validation_time :: DateTime.t(),
          inputs :: list(UnspentOutput.t())
        ) :: {:ok, logs :: list(String.t())} | {:error, ConditionRejected.t() | Failure.t()}
  def execute_condition(
        condition_key,
        contract = %Contract{conditions: conditions},
        transaction = %Transaction{},
        maybe_recipient,
        datetime,
        inputs
      ) do
    conditions
    |> Map.get(condition_key)
    |> do_execute_condition(
      condition_key,
      contract,
      transaction,
      datetime,
      maybe_recipient,
      inputs
    )
  rescue
    err ->
      stacktrace = __STACKTRACE__

      {:error,
       %Failure{
         error: err,
         user_friendly_error: append_line_to_error(err, stacktrace),
         logs: [],
         stacktrace: stacktrace
       }}
  end

  defp do_execute_condition(nil, :inherit, _, _, _, _, _), do: {:ok, []}

  defp do_execute_condition(nil, _, _, _, _, _, _) do
    {:error,
     %Failure{
       error: "Missing condition",
       user_friendly_error: "Missing condition",
       logs: [],
       stacktrace: []
     }}
  end

  defp do_execute_condition(
         %Conditions{args: args, subjects: subjects},
         condition_key,
         contract = %Contract{
           version: version,
           transaction: %Transaction{address: contract_address}
         },
         transaction = %Transaction{address: tx_address},
         datetime,
         maybe_recipient,
         inputs
       ) do
    named_action_constants = Interpreter.get_named_action_constants(args, maybe_recipient)

    condition_constants =
      get_condition_constants(condition_key, contract, transaction, datetime, inputs)

    key =
      {:execute_condition, condition_key, contract_address, tx_address, datetime,
       inputs_digest(inputs)}

    cache_interpreter_execute(
      fn ->
        case Interpreter.execute_condition(
               version,
               subjects,
               Map.merge(named_action_constants, condition_constants)
             ) do
          {:ok, logs} -> {:ok, logs}
          {:error, subject, logs} -> {:error, %ConditionRejected{subject: subject, logs: logs}}
        end
      end,
      key,
      timeout_err_msg: "Condition's execution timed-out",
      rescue_err: :condition_failure
    )
  end

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
         contract = %Contract{
           transaction: contract_tx,
           functions: functions,
           version: contract_version,
           state: state
         },
         transaction = %Transaction{
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{
               consumed_inputs: consumed_inputs,
               unspent_outputs: unspent_outputs
             }
           }
         },
         datetime,
         inputs
       ) do
    new_inputs =
      inputs
      |> Enum.reject(fn input ->
        Enum.any?(
          consumed_inputs,
          &(&1.unspent_output.type == input.type and &1.unspent_output.from == input.from)
        )
      end)
      |> Enum.concat(unspent_outputs)

    next_constants =
      transaction
      |> Constants.from_transaction(contract_version)
      |> Constants.set_balance(new_inputs)

    previous_contract_constants =
      contract_tx
      |> Constants.from_transaction(contract_version)
      |> Constants.set_balance(inputs)

    %{
      "previous" => previous_contract_constants,
      "next" => next_constants,
      :time_now => DateTime.to_unix(datetime),
      :functions => functions,
      :encrypted_seed => Contract.get_encrypted_seed(contract),
      :state => state
    }
  end

  defp get_condition_constants(
         _,
         contract = %Contract{
           transaction: contract_tx,
           functions: functions,
           version: contract_version,
           state: state
         },
         transaction,
         datetime,
         inputs
       ) do
    contract_constants =
      contract_tx
      |> Constants.from_transaction(contract_version)
      |> Constants.set_balance(inputs)

    %{
      "transaction" => Constants.from_transaction(transaction, contract_version),
      "contract" => contract_constants,
      :time_now => DateTime.to_unix(datetime),
      :functions => functions,
      :encrypted_seed => Contract.get_encrypted_seed(contract),
      :state => state
    }
  end

  # create a new transaction with the same code
  defp generate_next_tx(%Transaction{data: %TransactionData{code: code}}) do
    %Transaction{
      type: :contract,
      data: %TransactionData{
        code: code
      }
    }
  end

  defp append_line_to_error(err, stacktrace) do
    case Enum.find_value(stacktrace, fn
           {_, _, _, [file: 'nofile', line: line]} ->
             line

           _ ->
             false
         end) do
      line when is_integer(line) ->
        Exception.message(err) <> " - L#{line}"

      _ ->
        Exception.message(err)
    end
  end

  defp cache_interpreter_execute(fun, key, opts) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    rescue_err = Keyword.get(opts, :rescue_err, :execution_failure)

    func = fn ->
      try do
        fun.()
      rescue
        err ->
          # error from the code (ex: 1 + "abc")
          {:error, err, __STACKTRACE__}
      end
    end

    # We set the maximum timeout for a transaction to be processed before the kill the cache
    case Utils.JobCache.get!(key, function: func, timeout: timeout, ttl: 60_000) do
      {:error, err, stacktrace} ->
        {:error,
         %Failure{
           user_friendly_error: append_line_to_error(err, stacktrace),
           error: rescue_err,
           stacktrace: stacktrace,
           logs: []
         }}

      result ->
        result
    end
  rescue
    _ ->
      timeout_err_msg = Keyword.get(opts, :timeout_err_msg, "Contract's execution timeouts")
      {:error, %Failure{user_friendly_error: timeout_err_msg, error: :timeout}}
  end

  defp inputs_digest(inputs) do
    inputs
    |> Enum.map(fn %UnspentOutput{from: from, type: type} ->
      <<from::binary, UnspentOutput.type_to_str(type)::binary>>
    end)
    |> :erlang.list_to_binary()
    |> then(fn binary ->
      :crypto.hash(:sha256, binary)
    end)
  end
end
