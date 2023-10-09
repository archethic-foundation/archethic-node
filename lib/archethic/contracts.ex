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
  alias __MODULE__.State

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

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
          maybe_state_utxo :: nil | UnspentOutput.t(),
          opts :: Keyword.t()
        ) :: Contract.Result.t()
  def execute_trigger(
        trigger_type,
        contract = %Contract{transaction: contract_tx},
        maybe_trigger_tx,
        maybe_recipient,
        maybe_state_utxo \\ nil,
        opts \\ []
      ) do
    state = State.from_utxo(maybe_state_utxo)

    # TODO: trigger_tx & recipient should be transformed into recipient here
    # TODO: rescue should be done in here as well
    # TODO: implement timeout

    case Interpreter.execute_trigger(
           trigger_type,
           contract,
           state,
           maybe_trigger_tx,
           maybe_recipient,
           opts
         ) do
      {:ok, nil, next_state, logs} ->
        case State.to_utxo(next_state) do
          {:ok, nil} ->
            # empty state
            %Contract.Result.Noop{
              next_state_utxo: nil,
              logs: logs
            }

          {:ok, ^maybe_state_utxo} ->
            # output state == input state
            %Contract.Result.Noop{
              next_state_utxo: maybe_state_utxo,
              logs: logs
            }

          {:ok, state_utxo} ->
            # state changed, we "forward" the same transaction
            %Contract.Result.Success{
              logs: logs,
              next_tx: generate_next_tx(contract_tx),
              next_state_utxo: state_utxo
            }

          {:error, :state_too_big} ->
            %Contract.Result.Error{
              logs: [],
              error: "Execution was successful but the state exceed the threshold",
              stacktrace: [],
              user_friendly_error: "Execution was successful but the state exceed the threshold"
            }
        end

      {:ok, next_tx, next_state, logs} ->
        case State.to_utxo(next_state) do
          {:ok, maybe_utxo} ->
            %Contract.Result.Success{
              logs: logs,
              next_tx: next_tx,
              next_state_utxo: maybe_utxo
            }

          {:error, :state_too_big} ->
            %Contract.Result.Error{
              logs: [],
              error: "Execution was successful but the state exceed the threshold",
              stacktrace: [],
              user_friendly_error: "Execution was successful but the state exceed the threshold"
            }
        end

      {:error, err} ->
        %Contract.Result.Error{
          logs: [],
          error: err,
          stacktrace: [],
          user_friendly_error: err
        }

      {:error, err, stacktrace, logs} ->
        %Contract.Result.Error{
          logs: logs,
          error: err,
          stacktrace: stacktrace,
          user_friendly_error: append_line_to_error(err, stacktrace)
        }
    end
  end

  @doc """
  Execute contract's function
  """
  @spec execute_function(
          contract :: Contract.t(),
          function_name :: String.t(),
          args_values :: list(),
          maybe_state_utxo :: nil | UnspentOutput.t()
        ) ::
          {:ok, result :: any()}
          | {:error, :function_failure}
          | {:error, :function_does_not_exist}
          | {:error, :function_is_private}
          | {:error, :timeout}

  def execute_function(
        contract = %Contract{transaction: contract_tx, version: contract_version},
        function_name,
        args_values,
        maybe_state_utxo \\ nil
      ) do
    case get_function_from_contract(contract, function_name, args_values) do
      {:ok, function} ->
        constants = %{
          "contract" => Constants.from_contract_transaction(contract_tx, contract_version),
          :time_now => DateTime.utc_now() |> DateTime.to_unix(),
          :encrypted_seed => Contract.get_encrypted_seed(contract),
          :state => State.from_utxo(maybe_state_utxo)
        }

        task =
          Task.Supervisor.async_nolink(Archethic.TaskSupervisor, fn ->
            try do
              Interpreter.execute_function(function, constants, args_values)
            rescue
              _ ->
                # error from the code (ex: 1 + "abc")
                {:error, :function_failure}
            end
          end)

        # 500ms to execute or raise
        case Task.yield(task, 500) || Task.shutdown(task) do
          {:ok, {:error, reason}} ->
            {:error, reason}

          {:ok, reply} ->
            {:ok, reply}

          nil ->
            {:error, :timeout}
        end

      error ->
        error
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
  @spec load_transaction(Transaction.t(), list()) :: :ok
  defdelegate load_transaction(tx, opts), to: Loader

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
         contract = %Contract{
           transaction: contract_tx,
           functions: functions,
           version: contract_version
         },
         transaction,
         datetime
       ) do
    maybe_state_utxo = State.get_utxo_from_transaction(contract_tx)

    %{
      "previous" => Constants.from_contract_transaction(contract_tx, contract_version),
      "next" => Constants.from_contract_transaction(transaction, contract_version),
      :time_now => DateTime.to_unix(datetime),
      :functions => functions,
      :encrypted_seed => Contract.get_encrypted_seed(contract),
      :state => State.from_utxo(maybe_state_utxo)
    }
  end

  defp get_condition_constants(
         _,
         contract = %Contract{
           transaction: contract_tx,
           functions: functions,
           version: contract_version
         },
         transaction,
         datetime
       ) do
    maybe_state_utxo = State.get_utxo_from_transaction(contract_tx)

    %{
      "transaction" => Constants.from_transaction(transaction, contract_version),
      "contract" => Constants.from_contract_transaction(contract_tx, contract_version),
      :time_now => DateTime.to_unix(datetime),
      :functions => functions,
      :encrypted_seed => Contract.get_encrypted_seed(contract),
      :state => State.from_utxo(maybe_state_utxo)
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
end
