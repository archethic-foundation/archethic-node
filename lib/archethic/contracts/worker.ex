defmodule Archethic.Contracts.Worker do
  @moduledoc false

  alias Archethic.Account
  alias Archethic.ContractRegistry
  alias Archethic.Contracts
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Contract.ActionWithoutTransaction
  alias Archethic.Contracts.Contract.ActionWithTransaction
  alias Archethic.Contracts.Contract.Failure
  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.Mining.Fee
  alias Archethic.OracleChain
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.PubSub
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.Utils
  alias Archethic.Utils.DetectNodeResponsiveness
  alias Crontab.CronExpression.Parser, as: CronParser

  @extended_mode? Mix.env() != :prod

  require Logger

  use GenServer
  @vsn Mix.Project.config()[:version]

  def start_link(contract = %Contract{transaction: %Transaction{address: address}}) do
    GenServer.start_link(__MODULE__, contract, name: via_tuple(address))
  end

  @doc """
  Execute a transaction in the context of the contract with a given recipient.

  If the condition are respected a new transaction will be initiated
  """
  @spec execute(binary(), Transaction.t(), Recipient.t()) ::
          :ok | {:error, :no_transaction_trigger} | {:error, :condition_not_respected}
  def execute(resolved_address, tx = %Transaction{}, recipient = %Recipient{}) do
    GenServer.cast(via_tuple(resolved_address), {:execute, tx, recipient})
  end

  def init(contract = %Contract{}) do
    # Set trap_exit globally for the process
    Process.flag(:trap_exit, true)
    {:ok, %{contract: contract}, {:continue, :start_schedulers}}
  end

  def handle_continue(:start_schedulers, state = %{contract: %Contract{triggers: triggers}}) do
    triggers_type = Map.keys(triggers)

    new_state =
      Enum.reduce(triggers_type, state, fn trigger_type, acc ->
        case schedule_trigger(trigger_type, triggers_type) do
          timer when is_reference(timer) ->
            Map.update(acc, :timers, %{trigger_type => timer}, &Map.put(&1, trigger_type, timer))

          _ ->
            acc
        end
      end)

    {:noreply, new_state}
  end

  # TRIGGER: TRANSACTION
  def handle_cast({:execute, trigger_tx, recipient = %Recipient{}}, state = %{contract: contract}) do
    trigger = Contract.get_trigger_for_recipient(recipient)

    execute_contract(contract, trigger, trigger_tx, recipient)

    {:noreply, state}
  end

  # TRIGGER: DATETIME
  def handle_info({:trigger, trigger_type = {:datetime, _}}, state = %{contract: contract}) do
    execute_contract(contract, trigger_type, nil, nil)

    {:noreply, Map.update!(state, :timers, &Map.delete(&1, trigger_type))}
  end

  # TRIGGER: INTERVAL
  def handle_info(
        {:trigger, trigger_type = {:interval, interval}},
        state = %{contract: contract = %Contract{triggers: triggers}}
      ) do
    execute_contract(contract, trigger_type, nil, nil)

    interval_timer = schedule_trigger({:interval, interval}, Map.keys(triggers))
    {:noreply, put_in(state, [:timers, :interval], interval_timer)}
  end

  # TRIGGER: ORACLE
  def handle_info(
        {:new_transaction, tx_address, :oracle, _timestamp},
        state = %{contract: contract}
      ) do
    trigger_datetime = DateTime.utc_now()
    {:ok, oracle_tx} = TransactionChain.get_transaction(tx_address)

    if Contracts.valid_condition?(:oracle, contract, oracle_tx, nil, trigger_datetime) do
      execute_contract(contract, :oracle, oracle_tx, nil)
    end

    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, _}, state) do
    {:noreply, state}
  end

  # ----------------------------------------------
  defp via_tuple(address) do
    {:via, Registry, {ContractRegistry, address}}
  end

  defp execute_contract(
         contract = %Contract{transaction: %Transaction{address: contract_address}},
         trigger,
         maybe_trigger_tx,
         maybe_recipient
       ) do
    meta = log_metadata(contract_address, maybe_trigger_tx)
    Logger.debug("Contract execution started (trigger=#{inspect(trigger)})", meta)

    with true <- has_minimum_fees?(contract_address),
         %ActionWithTransaction{next_tx: next_tx} <-
           Contracts.execute_trigger(trigger, contract, maybe_trigger_tx, maybe_recipient),
         index = TransactionChain.get_size(contract_address),
         {:ok, next_tx} <- Contract.sign_next_transaction(contract, next_tx, index),
         contract_context <-
           get_contract_context(trigger, maybe_trigger_tx, maybe_recipient),
         :ok <- send_transaction(contract_context, next_tx) do
      Logger.debug("Contract execution success", meta)
    else
      %ActionWithoutTransaction{} ->
        Logger.debug("Contract execution success but there is no new transaction", meta)

      %Failure{user_friendly_error: reason} ->
        Logger.debug("Contract execution failed: #{inspect(reason)}", meta)

      _ ->
        Logger.debug("Contract execution failed", meta)
    end
  end

  defp get_contract_context(:oracle, %Transaction{address: address}, _) do
    %Contract.Context{
      status: :tx_output,
      trigger: {:oracle, address},
      timestamp: DateTime.utc_now()
    }
  end

  defp get_contract_context({:interval, interval}, _, _) do
    interval_datetime = Utils.get_current_time_for_interval(interval)

    %Contract.Context{
      status: :tx_output,
      trigger: {:interval, interval, interval_datetime},
      timestamp: DateTime.utc_now()
    }
  end

  defp get_contract_context(trigger = {:datetime, _}, _, _) do
    %Contract.Context{
      status: :tx_output,
      trigger: trigger,
      timestamp: DateTime.utc_now()
    }
  end

  defp get_contract_context({:transaction, _, _}, %Transaction{address: address}, recipient) do
    # In a next issue, we'll have different status such as :no_output and :failure
    %Contract.Context{
      status: :tx_output,
      trigger: {:transaction, address, recipient},
      timestamp: DateTime.utc_now()
    }
  end

  defp schedule_trigger(trigger = {:interval, interval}, triggers_type) do
    now = DateTime.utc_now()

    next_tick = interval |> CronParser.parse!(@extended_mode?) |> Utils.next_date(now)

    # do not allow an interval trigger if there is a datetime trigger at same time
    # because one of them would get a "transaction is already mining"
    next_tick =
      if {:datetime, next_tick} in triggers_type do
        Logger.debug(
          "Contract scheduler skips next tick for trigger=interval because there is a trigger=datetime at the same time that takes precedence"
        )

        interval |> CronParser.parse!(@extended_mode?) |> Utils.next_date(next_tick)
      else
        next_tick
      end

    Process.send_after(self(), {:trigger, trigger}, DateTime.diff(next_tick, now, :millisecond))
  end

  defp schedule_trigger(trigger = {:datetime, datetime = %DateTime{}}, _triggers_type) do
    seconds = DateTime.diff(datetime, DateTime.utc_now())

    if seconds > 0 do
      Process.send_after(self(), {:trigger, trigger}, seconds * 1000)
    end
  end

  defp schedule_trigger(:oracle, _triggers_type) do
    PubSub.register_to_new_transaction_by_type(:oracle)
  end

  defp schedule_trigger(_trigger_type, _triggers_type), do: :ok

  defp send_transaction(contract_context, next_transaction) do
    validation_nodes = get_validation_nodes(next_transaction)

    # The first storage node of the contract initiate the sending of the new transaction
    if trigger_node?(validation_nodes) do
      Archethic.send_new_transaction(next_transaction, contract_context: contract_context)
    else
      DetectNodeResponsiveness.start_link(
        next_transaction.address,
        length(validation_nodes),
        fn count ->
          Logger.info("contract transaction ...attempt #{count}")

          if trigger_node?(validation_nodes, count) do
            Archethic.send_new_transaction(next_transaction, contract_context: contract_context)
          end
        end
      )

      :ok
    end
  end

  defp get_validation_nodes(next_transaction = %Transaction{}) do
    next_transaction
    |> Transaction.previous_address()
    |> Election.chain_storage_nodes(P2P.authorized_and_available_nodes())
  end

  defp trigger_node?(validation_nodes, count \\ 0) do
    %Node{first_public_key: key} = validation_nodes |> Enum.at(count)
    key == Crypto.first_node_public_key()
  end

  defp has_minimum_fees?(contract_address) do
    minimum_fees =
      DateTime.utc_now()
      |> OracleChain.get_uco_price()
      |> Keyword.get(:usd)
      |> Fee.base_fee()

    case Account.get_balance(contract_address) do
      %{uco: uco_balance} when uco_balance >= minimum_fees ->
        true

      _ ->
        Logger.debug("Not enough funds to pay the minimum fee",
          contract: Base.encode16(contract_address)
        )

        false
    end
  end

  defp log_metadata(contract_address, nil) do
    [contract: Base.encode16(contract_address)]
  end

  defp log_metadata(contract_address, %Transaction{type: type, address: address}) do
    [
      transaction_address: Base.encode16(address),
      transaction_type: type,
      contract: Base.encode16(contract_address)
    ]
  end
end
