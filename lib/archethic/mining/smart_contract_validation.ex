defmodule Archethic.Mining.SmartContractValidation do
  @moduledoc """
  This module provides functions for validating smart contracts remotely.
  """

  alias Archethic.Contracts
  alias Archethic.Contracts.Contract.State
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Contract.ActionWithTransaction
  alias Archethic.Crypto
  alias Archethic.BeaconChain
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Message.SmartContractCallValidation
  alias Archethic.P2P.Message.ValidateSmartContractCall
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction

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
        ) :: {true, fee :: non_neg_integer()} | {false, 0}
  def validate_contract_calls(
        recipients,
        transaction = %Transaction{},
        validation_time = %DateTime{}
      ) do
    TaskSupervisor
    |> Task.Supervisor.async_stream_nolink(
      recipients,
      &request_contract_validation(&1, transaction, validation_time),
      timeout: @timeout + 500,
      ordered: false,
      on_timeout: :kill_task
    )
    |> Enum.reduce_while({true, 0}, fn
      {:ok, {_valid? = true, fee}}, {true, total_fee} -> {:cont, {true, total_fee + fee}}
      _, _ -> {:halt, {false, 0}}
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
      Enum.reduce(results, &priorize/2)
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
      {:ok, %SmartContractCallValidation{status: :ok, fee: fee}} -> {true, fee}
      _ -> {false, 0}
    end
  end

  @doc """
  Execute the contract if it's relevant and return a boolean if given transaction is genuine.
  It also return the result because it's need to extract the state
  """
  @spec valid_contract_execution?(
          contract_context :: Contract.Context.t(),
          prev_tx :: Transaction.t(),
          genesis_address :: Crypto.prepended_hash(),
          next_tx :: Transaction.t()
        ) :: {boolean(), State.encoded() | nil}
  def valid_contract_execution?(
        %Contract.Context{status: status, trigger: trigger, timestamp: timestamp, inputs: inputs},
        prev_tx,
        genesis_address,
        next_tx
      ) do
    trigger_type = trigger_to_trigger_type(trigger)
    recipient = trigger_to_recipient(trigger)
    opts = trigger_to_execute_opts(trigger)
    inputs = VersionedUnspentOutput.unwrap_unspent_outputs(inputs)

    with {:ok, maybe_trigger_tx} <-
           validate_trigger(trigger, timestamp, genesis_address, inputs),
         {:ok, contract} <-
           Contract.from_transaction(prev_tx),
         {:ok, res} <-
           Contracts.execute_trigger(
             trigger_type,
             contract,
             maybe_trigger_tx,
             recipient,
             inputs,
             opts
           ),
         {:ok, encoded_state} <-
           validate_result(res, next_tx, status) do
      {true, encoded_state}
    else
      _ -> {false, nil}
    end
  end

  def valid_contract_execution?(
        _contract_context = nil,
        prev_tx = %Transaction{data: %TransactionData{code: code}},
        _genesis_address,
        _next_tx = %Transaction{}
      )
      when code != "" do
    # only contract without triggers (with only conditions) are allowed to NOT have a Contract.Context
    if prev_tx |> Contract.from_transaction!() |> Contract.contains_trigger?(),
      do: {false, nil},
      else: {true, nil}
  end

  def valid_contract_execution?(_, _, _, _), do: {true, nil}

  defp validate_result(
         %ActionWithTransaction{next_tx: expected_next_tx, encoded_state: encoded_state},
         next_tx,
         _status = :tx_output
       ) do
    same_payload? =
      next_tx
      |> Contract.remove_seed_ownership()
      |> Transaction.same_payload?(expected_next_tx)

    if same_payload?, do: {:ok, encoded_state}, else: :error
  end

  defp validate_result(_, _, _), do: :error

  defp validate_trigger({:datetime, datetime}, validation_datetime, _, _) do
    if within_drift_tolerance?(validation_datetime, datetime) do
      {:ok, nil}
    else
      :invalid_triggers_execution
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
      :invalid_triggers_execution
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

        :invalid_triggers_execution
    end
  end

  defp validate_trigger({:oracle, address}, _, _, _) do
    storage_nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    case TransactionChain.fetch_transaction(address, storage_nodes) do
      {:ok, tx} ->
        {:ok, tx}

      {:error, _} ->
        # todo: it might too strict to say that it's invalid in some cases (timeout)
        :invalid_triggers_execution
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

  @doc """
  Priorize validation call

  ## Examples

      iex> SmartContractValidation.priorize(%SmartContractCallValidation{status: {:error, :transaction_not_exists}}, %SmartContractCallValidation{status: :ok})
      %SmartContractCallValidation{status: :ok}

      iex> SmartContractValidation.priorize(%SmartContractCallValidation{status: :ok}, %SmartContractCallValidation{status: {:error, :transaction_not_exists}})
      %SmartContractCallValidation{status: :ok}

      iex> SmartContractValidation.priorize(%SmartContractCallValidation{status: {:error, :invalid_execution}}, %SmartContractCallValidation{status: {:error, :transaction_not_exists}})
      %SmartContractCallValidation{status: {:error, :invalid_execution}}

      iex> SmartContractValidation.priorize(%SmartContractCallValidation{status: {:error, :transaction_not_exists}}, %SmartContractCallValidation{status: {:error, :invalid_execution}})
      %SmartContractCallValidation{status: {:error, :invalid_execution}}

      iex> SmartContractValidation.priorize(%SmartContractCallValidation{status: :ok}, %SmartContractCallValidation{status: {:error, :invalid_execution}})
      %SmartContractCallValidation{status: {:error, :invalid_execution}}

      iex> SmartContractValidation.priorize(%SmartContractCallValidation{status: {:error, :invalid_execution}}, %SmartContractCallValidation{status: :ok})
      %SmartContractCallValidation{status: {:error, :invalid_execution}}
  """
  @spec priorize(SmartContractCallValidation.t(), SmartContractCallValidation.t()) ::
          SmartContractCallValidation.t()
  def priorize(a = %SmartContractCallValidation{status: :ok}, %SmartContractCallValidation{
        status: {:error, :transaction_not_exists}
      }),
      do: a

  def priorize(
        %SmartContractCallValidation{status: {:error, :transaction_not_exists}},
        b = _
      ),
      do: b

  def priorize(a = %SmartContractCallValidation{status: {:error, :invalid_execution}}, _), do: a

  def priorize(
        %SmartContractCallValidation{status: :ok},
        b = %SmartContractCallValidation{status: {:error, :invalid_execution}}
      ),
      do: b

  def priorize(a, b) when a == b, do: a
end
