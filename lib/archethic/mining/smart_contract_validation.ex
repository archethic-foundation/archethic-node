defmodule Archethic.Mining.SmartContractValidation do
  @moduledoc """
  This module provides functions for validating smart contracts remotely.
  """

  alias Archethic.Contracts
  alias Archethic.Contracts.Contract.State
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Contract.Failure
  alias Archethic.Contracts.Contract.ActionWithTransaction
  alias Archethic.Crypto
  alias Archethic.BeaconChain
  alias Archethic.Election
  alias Archethic.Mining.Error
  alias Archethic.P2P
  alias Archethic.P2P.Message.SmartContractCallValidation
  alias Archethic.P2P.Message.ValidateSmartContractCall
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction

  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TaskSupervisor

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.DateChecker, as: CronDateChecker

  @extended_mode? Mix.env() != :prod
  @timeout 5_000

  require Logger

  @doc """
  Determine if the smart contracts conditions are valid according to the given transaction

  This function requests storage nodes of the contract address to execute the transaction validation and return assertion about the execution
  """
  @spec validate_contract_calls(
          recipients :: list(Recipient.t()),
          transaction :: Transaction.t(),
          validation_time :: DateTime.t()
        ) :: {:ok, fee :: non_neg_integer()} | {:error, error :: Error.t()}
  def validate_contract_calls([], _, _), do: {:ok, 0}

  def validate_contract_calls(
        recipients,
        transaction = %Transaction{},
        validation_time = %DateTime{}
      ) do
    default_error =
      Error.new(:invalid_recipients_execution, "Failed to validate call due to timeout")

    TaskSupervisor
    |> Task.Supervisor.async_stream_nolink(
      recipients,
      &request_contract_validation(&1, transaction, validation_time),
      timeout: @timeout + 500,
      ordered: false,
      on_timeout: :kill_task,
      max_concurrency: length(recipients)
    )
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Enum.reduce_while({:error, default_error}, fn
      {:ok, {:ok, fee}}, {:error, _} -> {:cont, {:ok, fee}}
      {:ok, {:ok, fee}}, {:ok, total_fee} -> {:cont, {:ok, total_fee + fee}}
      {:ok, {:error, error}}, _ -> {:halt, error}
    end)
  end

  defp request_contract_validation(
         recipient = %Recipient{address: genesis_address},
         transaction = %Transaction{},
         validation_time
       ) do
    previous_summary_time = BeaconChain.previous_summary_time(DateTime.utc_now())

    genesis_nodes =
      genesis_address
      |> Election.chain_storage_nodes(P2P.authorized_and_available_nodes())
      |> Election.get_synchronized_nodes_before(previous_summary_time)

    conflicts_resolver = fn results ->
      Enum.sort_by(results, fn
        %SmartContractCallValidation{status: :ok} -> 1
        %SmartContractCallValidation{status: {:error, :invalid_condition, _}} -> 2
        %SmartContractCallValidation{status: {:error, :invalid_execution, _}} -> 3
        %SmartContractCallValidation{status: {:error, :insufficient_funds}} -> 4
        %SmartContractCallValidation{status: {:error, :parsing_error, _}} -> 5
        %SmartContractCallValidation{status: {:error, :transaction_not_exists}} -> 6
      end)
      |> List.first()
    end

    case P2P.quorum_read(
           genesis_nodes,
           %ValidateSmartContractCall{
             recipient: recipient,
             transaction: transaction,
             timestamp: validation_time
           },
           conflicts_resolver,
           @timeout
         ) do
      {:ok, %SmartContractCallValidation{status: :ok, fee: fee}} ->
        {:ok, fee}

      {:ok, %SmartContractCallValidation{status: error_status}} ->
        data = %{"recipient" => Base.encode16(genesis_address)}
        {:error, format_error_status(error_status, data)}

      {:error, :network_issue} ->
        data = %{
          "recipient" => Base.encode16(genesis_address),
          "message" => "Failed to validate call due to timeout"
        }

        {:error, {:error, Error.new(:invalid_recipients_execution, data)}}
    end
  end

  defp format_error_status({:error, :transaction_not_exists}, data) do
    data = Map.put(data, "message", "Contract recipient does not exists")
    {:error, Error.new(:invalid_recipients_execution, data)}
  end

  defp format_error_status({:error, :insufficient_funds}, data) do
    data = Map.put(data, "message", "Contract has not enough funds to create the transaction")
    {:error, Error.new(:invalid_recipients_execution, data)}
  end

  defp format_error_status(
         {:error, :invalid_execution, %Failure{user_friendly_error: message, data: failure_data}},
         data
       ) do
    data = data |> Map.put("message", message) |> Map.put("data", failure_data)
    {:error, Error.new(:invalid_recipients_execution, data)}
  end

  defp format_error_status({:error, :invalid_condition, subject}, data) do
    data = Map.put(data, "message", "Invalid condition on #{subject}")
    {:error, Error.new(:invalid_recipients_execution, data)}
  end

  defp format_error_status({:error, :parsing_error, reason}, data) do
    data = data |> Map.put("message", "Error when parsing contract") |> Map.put("data", reason)
    {:error, Error.new(:invalid_recipients_execution, data)}
  end

  @doc """
  Execute the contract if it's relevant and return a boolean if given transaction is genuine.
  It also return the result because it's need to extract the state
  """
  @spec validate_contract_execution(
          contract_context :: Contract.Context.t(),
          prev_tx :: Transaction.t(),
          genesis_address :: Crypto.prepended_hash(),
          next_tx :: Transaction.t(),
          chain_unspent_outputs :: list(VersionedUnspentOutput.t())
        ) :: {:ok, State.encoded() | nil} | {:error, Error.t()}
  def validate_contract_execution(
        contract_context = %Contract.Context{
          status: status,
          trigger: trigger,
          timestamp: timestamp
        },
        prev_tx,
        genesis_address,
        next_tx,
        chain_unspent_outputs
      ) do
    chain_unspent_outputs = VersionedUnspentOutput.unwrap_unspent_outputs(chain_unspent_outputs)

    with {:ok, maybe_trigger_tx} <-
           validate_trigger(trigger, timestamp, genesis_address, chain_unspent_outputs),
         {:ok, contract} <- parse_contract(prev_tx),
         {:ok, res} <- execute_trigger(contract_context, contract, maybe_trigger_tx) do
      validate_result(res, next_tx, status)
    end
  end

  def validate_contract_execution(
        _contract_context = nil,
        prev_tx = %Transaction{data: %TransactionData{code: code}},
        _genesis_address,
        _next_tx = %Transaction{},
        _chain_unspent_outputs
      )
      when code != "" do
    # only contract without triggers (with only conditions) are allowed to NOT have a Contract.Context
    if prev_tx |> Contract.from_transaction!() |> Contract.contains_trigger?(),
      do: {:error, Error.new(:invalid_contract_execution, "Contract has not been triggered")},
      else: {:ok, nil}
  end

  def validate_contract_execution(_, _, _, _, _), do: {:ok, nil}

  @doc """
  Validate contract inherit constraint
  """
  @spec validate_inherit_condition(
          prev_tx :: Transaction.t(),
          next_tx :: Transaction.t(),
          contract_inputs :: list(VersionedUnspentOutput.t())
        ) :: :ok | {:error, Error.t()}
  def validate_inherit_condition(
        prev_tx = %Transaction{data: %TransactionData{code: code}},
        next_tx = %Transaction{validation_stamp: %ValidationStamp{timestamp: validation_time}},
        contract_inputs
      )
      when code != "" do
    case Contracts.execute_condition(
           :inherit,
           Contract.from_transaction!(prev_tx),
           next_tx,
           nil,
           validation_time,
           VersionedUnspentOutput.unwrap_unspent_outputs(contract_inputs)
         ) do
      {:ok, _logs} ->
        :ok

      {:error, %Failure{user_friendly_error: user_friendly_error, data: data}} ->
        {:error, Error.new(:invalid_inherit_constraints, data || user_friendly_error)}

      {:error, _} ->
        {:error, Error.new(:invalid_inherit_constraints)}
    end
  end

  def validate_inherit_condition(_, _, _), do: :ok

  defp validate_trigger({:datetime, datetime}, validation_datetime, _, _) do
    if within_drift_tolerance?(validation_datetime, datetime) do
      {:ok, nil}
    else
      error =
        Error.new(:invalid_contract_execution, %{
          "message" => "Invalid trigger datetime",
          "triggerDatetime" => DateTime.to_unix(datetime, :second),
          "validationTime" => DateTime.to_unix(validation_datetime, :second)
        })

      {:error, error}
    end
  end

  defp validate_trigger({:interval, interval, interval_datetime}, validation_datetime, _, _) do
    matches_date? =
      interval
      |> CronParser.parse!(@extended_mode?)
      |> CronDateChecker.matches_date?(DateTime.to_naive(interval_datetime))

    if matches_date? && within_drift_tolerance?(validation_datetime, interval_datetime) do
      {:ok, nil}
    else
      error =
        Error.new(:invalid_contract_execution, %{
          "message" => "Invalid trigger interval",
          "intervalTime" => DateTime.to_unix(interval_datetime, :second),
          "validationTime" => DateTime.to_unix(validation_datetime, :second)
        })

      {:error, error}
    end
  end

  defp validate_trigger({:transaction, address, recipient}, _, contract_genesis_address, inputs) do
    storage_nodes = Election.storage_nodes(address, P2P.authorized_and_available_nodes())

    with true <-
           Enum.any?(
             inputs,
             &(&1.type == :call and &1.from == address)
           ),
         {:ok, tx} <- TransactionChain.fetch_transaction(address, storage_nodes),
         true <- Enum.member?(tx.data.recipients, recipient) do
      {:ok, tx}
    else
      _ ->
        Logger.error("Contract was wrongly triggered by transaction",
          transaction_address: Base.encode16(address),
          contract: Base.encode16(contract_genesis_address)
        )

        error =
          Error.new(:invalid_contract_execution, %{
            "message" => "Invalid trigger transaction",
            "triggerAddress" => Base.encode16(address)
          })

        {:error, error}
    end
  end

  defp validate_trigger({:oracle, address}, _, _, _) do
    storage_nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    case TransactionChain.fetch_transaction(address, storage_nodes) do
      {:ok, tx} ->
        {:ok, tx}

      {:error, _} ->
        # todo: it might too strict to say that it's invalid in some cases (timeout)
        error =
          Error.new(:invalid_contract_execution, %{
            "message" => "Invalid trigger oracle",
            "triggerAddress" => Base.encode16(address)
          })

        {:error, error}
    end
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

  # validation_time: practical date of trigger
  # datetime: theoretical date of trigger
  defp within_drift_tolerance?(validation_datetime, datetime) do
    DateTime.diff(validation_datetime, datetime) >= 0 and
      DateTime.diff(validation_datetime, datetime) < 10
  end

  defp parse_contract(prev_tx) do
    case Contract.from_transaction(prev_tx) do
      {:ok, contract} ->
        {:ok, contract}

      {:error, reason} ->
        error =
          Error.new(:invalid_contract_execution, %{
            "message" => "Cannot parse previous contract transaction",
            "data" => reason
          })

        {:error, error}
    end
  end

  defp execute_trigger(
         %Contract.Context{trigger: trigger, inputs: contract_inputs},
         contract,
         maybe_trigger_tx
       ) do
    trigger_type = trigger_to_trigger_type(trigger)
    recipient = trigger_to_recipient(trigger)
    opts = trigger_to_execute_opts(trigger)
    contract_inputs = VersionedUnspentOutput.unwrap_unspent_outputs(contract_inputs)

    case Contracts.execute_trigger(
           trigger_type,
           contract,
           maybe_trigger_tx,
           recipient,
           contract_inputs,
           opts
         ) do
      {:ok, res} ->
        {:ok, res}

      {:error, %Failure{user_friendly_error: message, data: data}} ->
        {:error, Error.new(:invalid_contract_execution, data || message)}
    end
  end

  defp validate_result(
         %ActionWithTransaction{next_tx: expected_next_tx, encoded_state: encoded_state},
         next_tx,
         _status = :tx_output
       ) do
    same_payload? =
      next_tx |> Contract.remove_seed_ownership() |> Transaction.same_payload?(expected_next_tx)

    if same_payload? do
      {:ok, encoded_state}
    else
      {:error,
       Error.new(:invalid_contract_execution, "Transaction does not match expected result")}
    end
  end

  defp validate_result(_, _, _),
    do:
      {:error, Error.new(:invalid_contract_execution, "Contract should not output a transaction")}
end
