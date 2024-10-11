defmodule Archethic.Contracts.Worker do
  @moduledoc false

  alias Archethic.ContractRegistry
  alias Archethic.Contracts
  alias Archethic.Contracts.InterpretedContract
  alias Archethic.Contracts.WasmSpec
  alias Archethic.Contracts.WasmContract
  alias Archethic.Contracts.WasmModule
  alias Archethic.Contracts.Contract.ActionWithoutTransaction
  alias Archethic.Contracts.Contract.ActionWithTransaction
  alias Archethic.Contracts.Contract.Failure
  alias Archethic.Contracts.Contract.Context
  alias Archethic.Contracts.Loader
  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.PubSub
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.Utils
  alias Archethic.Utils.DetectNodeResponsiveness

  @extended_mode? Mix.env() != :prod

  require Logger

  use GenStateMachine, callback_mode: :handle_event_function
  @vsn 2

  @schedule_trigger {:next_event, :internal, :start_schedulers}
  @process_trigger {:next_event, :internal, :process_next_trigger}
  @schedule_and_process_trigger [@schedule_trigger, @process_trigger]

  def start_link(opts) do
    genesis_address = Keyword.fetch!(opts, :genesis_address)
    GenStateMachine.start_link(__MODULE__, opts, name: via_tuple(genesis_address))
  end

  @doc """
  Request the worker to process the next trigger
  """
  @spec process_next_trigger(genesis_address :: Crypto.prepended_hash()) :: :ok
  def process_next_trigger(genesis_address),
    do: genesis_address |> via_tuple() |> GenStateMachine.cast(:process_next_trigger)

  @doc """
  Set a new contract version in the worker
  """
  @spec set_contract(
          genesis_address :: Crypto.prepended_hash(),
          contract :: InterpretedContract.t() | WasmContract.t(),
          execute_contract? :: boolean()
        ) :: :ok
  def set_contract(genesis_address, contract, execute_contract?) do
    genesis_address
    |> via_tuple()
    |> GenStateMachine.cast({:new_contract, contract, execute_contract?})
  end

  def init(opts) do
    # Set trap_exit globally for the process
    Process.flag(:trap_exit, true)

    PubSub.register_to_node_status()
    PubSub.register_to_node_update()

    contract = Keyword.fetch!(opts, :contract)
    genesis_address = Keyword.fetch!(opts, :genesis_address)

    data = %{contract: contract, genesis_address: genesis_address, self_triggers: []}

    if Archethic.up?() and P2P.authorized_and_available_node?(),
      do: {:ok, :waiting_trigger, data, @schedule_and_process_trigger},
      else: {:ok, :idle, data}
  end

  def handle_event(:internal, :start_schedulers, :idle, _data), do: :keep_state_and_data

  def handle_event(
        :internal,
        :start_schedulers,
        _state,
        data = %{contract: contract}
      ) do
    triggers_type = get_contract_trigger_types(contract)

    # stop all existing timers
    data = cancel_schedulers(data)

    new_data =
      Enum.reduce(triggers_type, data, fn trigger_type, acc ->
        case schedule_trigger(trigger_type, triggers_type) do
          timer when is_reference(timer) ->
            Map.update(acc, :timers, %{trigger_type => timer}, &Map.put(&1, trigger_type, timer))

          _ ->
            acc
        end
      end)

    {:next_state, :waiting_trigger, new_data}
  end

  def handle_event(:internal, :process_next_trigger, :idle, _data), do: :keep_state_and_data

  def handle_event(:internal, :process_next_trigger, _state, data) do
    # Take next trigger to process
    case get_next_trigger(data) do
      nil ->
        {:next_state, :waiting_trigger, data}

      trigger ->
        data = Map.update!(data, :self_triggers, fn t -> Enum.reject(t, &(&1 == trigger)) end)

        case handle_trigger(trigger, data) do
          {:ok, new_data} -> {:next_state, :working, new_data}
          {:error, new_data} -> {:keep_state, new_data, @process_trigger}
        end
    end
  end

  def handle_event(:cast, {:new_contract, contract, _}, :idle, data) do
    new_data = data |> Map.put(:contract, contract) |> Map.delete(:last_call_processed)
    {:keep_state, new_data}
  end

  def handle_event(:cast, {:new_contract, contract, execute_contract?}, _state, data) do
    new_data =
      data
      |> cancel_schedulers()
      |> Map.put(:contract, contract)
      |> Map.delete(:last_call_processed)

    next_events = if execute_contract?, do: @schedule_and_process_trigger, else: @schedule_trigger

    {:keep_state, new_data, next_events}
  end

  # TRIGGER: TRANSACTION
  def handle_event(:cast, :process_next_trigger, :waiting_trigger, data),
    do: {:keep_state, data, @process_trigger}

  def handle_event(:cast, :process_next_trigger, _state, _data), do: :keep_state_and_data

  def handle_event(
        :cast,
        :reparse_contract,
        _,
        data = %{contract: contract = %{transaction: contract_tx}}
      ) do
    case contract do
      # We need to reparse the contract to update the parsed contract in the state (triggers, etc.)
      %InterpretedContract{} ->
        {:keep_state, %{data | contract: InterpretedContract.from_transaction!(contract_tx)}}

      _ ->
        :keep_state_and_data
    end
  end

  # TRIGGER: DATETIME or INTERVAL
  def handle_event(:info, {:trigger, _}, :idle, _data), do: :keep_state_and_data

  def handle_event(:info, {:trigger, trigger_type}, :working, data) do
    new_data = Map.update!(data, :self_triggers, &(&1 ++ [trigger_type]))
    {:keep_state, new_data}
  end

  def handle_event(:info, {:trigger, trigger_type}, :waiting_trigger, data) do
    case handle_trigger(trigger_type, data) do
      {:ok, new_data} -> {:next_state, :working, new_data}
      {:error, new_data} -> {:keep_state, new_data, @process_trigger}
    end
  end

  # TRIGGER: ORACLE
  def handle_event(:info, {:new_transaction, _, _, _}, :idle, _data), do: :keep_state_and_data

  def handle_event(:info, {:new_transaction, tx_address, :oracle, _}, :working, data) do
    new_data = Map.update!(data, :self_triggers, &(&1 ++ [{:oracle, tx_address}]))
    {:keep_state, new_data}
  end

  def handle_event(:info, {:new_transaction, tx_address, :oracle, _}, :waiting_trigger, data) do
    case handle_trigger({:oracle, tx_address}, data) do
      {:ok, new_data} ->
        {:next_state, :working, new_data}

      {:error, new_data} ->
        {:keep_state, new_data, @process_trigger}
    end
  end

  # Node is up, starting schedulers
  def handle_event(:info, :node_up, :idle, data) do
    if P2P.authorized_and_available_node?(),
      do: {:next_state, :waiting_trigger, data, @schedule_and_process_trigger},
      else: :keep_state_and_data
  end

  # Node is down, stoping schedulers
  def handle_event(:info, :node_down, _state, data),
    do: {:next_state, :idle, cancel_schedulers(data)}

  def handle_event(:info, {:node_update, _}, :idle, data) do
    if P2P.authorized_and_available_node?() and Archethic.up?(),
      do: {:next_state, :waiting_trigger, data, @schedule_and_process_trigger},
      else: :keep_state_and_data
  end

  def handle_event(:info, {:node_update, _}, _, data) do
    if P2P.authorized_and_available_node?() and Archethic.up?(),
      do: :keep_state_and_data,
      else: {:next_state, :idle, cancel_schedulers(data)}
  end

  # Node responsiveness timeout
  def handle_event(
        :info,
        {:EXIT, _pid, _},
        _state,
        data = %{
          contract: %{transaction: %Transaction{address: contract_address}},
          genesis_address: genesis_address
        }
      ) do
    case Map.get(data, :last_call_processed) do
      nil ->
        :skip

      last_call_processed ->
        Loader.invalidate_call(genesis_address, contract_address, last_call_processed)
    end

    new_data = Map.delete(data, :last_call_processed)
    {:keep_state, new_data, @schedule_and_process_trigger}
  end

  def code_change(_old_vsn, state, data, _extra), do: {:ok, state, data}

  # ----------------------------------------------
  defp via_tuple(address) do
    {:via, Registry, {ContractRegistry, address}}
  end

  defp get_contract_trigger_types(%InterpretedContract{triggers: triggers}),
    do: Map.keys(triggers)

  defp get_contract_trigger_types(%WasmContract{
         module: %WasmModule{spec: %WasmSpec{triggers: triggers}}
       }) do
    Enum.map(triggers, & &1.type)
  end

  defp get_next_trigger(%{
         contract: %{transaction: %Transaction{address: contract_address}},
         genesis_address: genesis_address,
         self_triggers: []
       }) do
    case Loader.get_next_call(genesis_address, contract_address) do
      {trigger_tx, recipient} -> {:transaction, trigger_tx, recipient}
      nil -> nil
    end
  end

  defp get_next_trigger(%{self_triggers: self_triggers}), do: List.first(self_triggers)

  defp handle_trigger(
         trigger_type = {:datetime, _},
         data = %{genesis_address: genesis_address, contract: contract}
       ) do
    unspent_outputs = fetch_unspent_outputs(genesis_address)

    case execute_contract(contract, trigger_type, nil, nil, genesis_address, unspent_outputs) do
      :ok ->
        new_data = data |> Map.update!(:timers, &Map.delete(&1, trigger_type))
        {:ok, new_data}

      _ ->
        new_data = data |> Map.update!(:timers, &Map.delete(&1, trigger_type))
        {:error, new_data}
    end
  end

  defp handle_trigger(
         trigger_type = {:interval, interval},
         data = %{
           genesis_address: genesis_address,
           contract: contract
         }
       ) do
    unspent_outputs = fetch_unspent_outputs(genesis_address)

    case execute_contract(contract, trigger_type, nil, nil, genesis_address, unspent_outputs) do
      :ok ->
        new_data = data |> Map.update!(:timers, &Map.delete(&1, trigger_type))
        {:ok, new_data}

      _ ->
        interval_timer =
          schedule_trigger({:interval, interval}, get_contract_trigger_types(contract))

        new_data = put_in(data, [:timers, trigger_type], interval_timer)
        {:error, new_data}
    end
  end

  defp handle_trigger(
         {:oracle, tx_address},
         data = %{genesis_address: genesis_address, contract: contract}
       ) do
    trigger_datetime = DateTime.utc_now()

    unspent_outputs = fetch_unspent_outputs(genesis_address)

    with {:ok, oracle_tx} <- TransactionChain.get_transaction(tx_address),
         :ok <-
           execute_trigger(
             contract,
             :oracle,
             oracle_tx,
             nil,
             trigger_datetime,
             unspent_outputs,
             genesis_address
           ) do
      {:ok, data}
    else
      _ ->
        {:error, data}
    end
  end

  defp handle_trigger(
         {:transaction,
          trigger_tx = %Transaction{
            address: from,
            validation_stamp: %ValidationStamp{timestamp: timestamp}
          }, recipient},
         data = %{
           genesis_address: genesis_address,
           contract: contract = %{transaction: %Transaction{address: contract_address}}
         }
       ) do
    trigger = Recipient.get_trigger(recipient)
    unspent_outputs = fetch_unspent_outputs(genesis_address)

    case execute_trigger(
           contract,
           trigger,
           trigger_tx,
           recipient,
           timestamp,
           unspent_outputs,
           genesis_address
         ) do
      :ok ->
        {:ok, Map.put(data, :last_call_processed, from)}

      _ ->
        Loader.invalidate_call(genesis_address, contract_address, from)
        {:error, data}
    end
  end

  defp execute_trigger(
         contract = %InterpretedContract{},
         trigger,
         trigger_tx,
         recipient,
         timestamp,
         unspent_outputs,
         genesis_address
       ) do
    case Contracts.execute_condition(
           trigger,
           contract,
           trigger_tx,
           recipient,
           timestamp,
           VersionedUnspentOutput.unwrap_unspent_outputs(unspent_outputs)
         ) do
      {:ok, _logs} ->
        execute_contract(
          contract,
          trigger,
          trigger_tx,
          recipient,
          genesis_address,
          unspent_outputs
        )

      {:error, _} = e ->
        e
    end
  end

  defp execute_trigger(
         contract = %WasmContract{},
         trigger,
         trigger_tx,
         recipient,
         _timestamp,
         unspent_outputs,
         genesis_address
       ) do
    execute_contract(
      contract,
      trigger,
      trigger_tx,
      recipient,
      genesis_address,
      unspent_outputs
    )
  end

  defp execute_contract(
         contract = %{transaction: %Transaction{address: contract_address}},
         trigger,
         maybe_trigger_tx,
         maybe_recipient,
         contract_genesis_address,
         unspent_outputs
       ) do
    meta = log_metadata(contract_address, maybe_trigger_tx)
    Logger.debug("Contract execution started (trigger=#{inspect(trigger)})", meta)

    with {:ok, %ActionWithTransaction{next_tx: next_tx}} <-
           Contracts.execute_trigger(
             trigger,
             contract,
             maybe_trigger_tx,
             maybe_recipient,
             VersionedUnspentOutput.unwrap_unspent_outputs(unspent_outputs)
           ),
         index = TransactionChain.get_size(contract_address),
         {:ok, next_tx} <- Contracts.sign_next_transaction(contract, next_tx, index),
         contract_context <-
           get_contract_context(trigger, maybe_trigger_tx, maybe_recipient, unspent_outputs),
         :ok <- send_transaction(contract_context, next_tx, contract_genesis_address) do
      Logger.debug("Contract execution success", meta)
      :ok
    else
      {:ok, %ActionWithoutTransaction{}} ->
        Logger.debug("Contract execution success but there is no new transaction", meta)
        :error

      {:error, %Failure{user_friendly_error: reason}} ->
        Logger.debug("Contract execution failed: #{inspect(reason)}", meta)
        :error

      {:error, reason} ->
        Logger.debug("Contract execution failed: #{inspect(reason)}", meta)
        :error
    end
  end

  defp get_contract_context(:oracle, %Transaction{address: address}, _, unspent_outputs) do
    %Context{
      status: :tx_output,
      trigger: {:oracle, address},
      timestamp: DateTime.utc_now(),
      inputs: unspent_outputs
    }
  end

  defp get_contract_context({:interval, interval}, _, _, unspent_outputs) do
    interval_datetime = Utils.get_current_time_for_interval(interval)

    %Context{
      status: :tx_output,
      trigger: {:interval, interval, interval_datetime},
      timestamp: DateTime.utc_now(),
      inputs: unspent_outputs
    }
  end

  defp get_contract_context(trigger = {:datetime, _}, _, _, unspent_outputs) do
    %Context{
      status: :tx_output,
      trigger: trigger,
      timestamp: DateTime.utc_now(),
      inputs: unspent_outputs
    }
  end

  defp get_contract_context(
         {:transaction, _, _},
         %Transaction{address: address},
         recipient,
         unspent_outputs
       ) do
    # In a next issue, we'll have different status such as :no_output and :failure
    %Context{
      status: :tx_output,
      trigger: {:transaction, address, recipient},
      timestamp: DateTime.utc_now(),
      inputs: unspent_outputs
    }
  end

  defp schedule_trigger(trigger = {:interval, interval}, triggers_type) do
    now = DateTime.utc_now()

    next_tick = Utils.next_date(interval, now, @extended_mode?)

    # do not allow an interval trigger if there is a datetime trigger at same time
    # because one of them would get a "transaction is already mining"
    next_tick =
      if {:datetime, next_tick} in triggers_type do
        Logger.debug(
          "Contract scheduler skips next tick for trigger=interval because there is a trigger=datetime at the same time that takes precedence"
        )

        Utils.next_date(interval, next_tick, @extended_mode?)
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

  defp cancel_schedulers(state) do
    {timers, new_state} = Map.pop(state, :timers, %{})
    timers |> Map.values() |> Enum.each(&Process.cancel_timer/1)
    PubSub.unregister_to_new_transaction_by_type(:oracle)

    new_state
  end

  defp send_transaction(contract_context, next_transaction, contract_genesis_address) do
    genesis_nodes = get_sorted_genesis_nodes(next_transaction, contract_genesis_address)

    # The first storage node of the contract initiate the sending of the new transaction
    if trigger_node?(genesis_nodes) do
      Archethic.send_new_transaction(next_transaction, contract_context: contract_context)
    else
      DetectNodeResponsiveness.start_link(
        next_transaction.address,
        length(genesis_nodes),
        fn count ->
          Logger.info("contract transaction ...attempt #{count}")

          if trigger_node?(genesis_nodes, count) do
            Archethic.send_new_transaction(next_transaction, contract_context: contract_context)
          end
        end
      )

      :ok
    end
  end

  defp get_sorted_genesis_nodes(%Transaction{address: address}, contract_genesis_address) do
    Election.storage_nodes_sorted_by_address(
      contract_genesis_address,
      address,
      P2P.authorized_and_available_nodes()
    )
  end

  defp trigger_node?(validation_nodes, count \\ 0) do
    %Node{first_public_key: key} = validation_nodes |> Enum.at(count)
    key == Crypto.first_node_public_key()
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

  defp fetch_unspent_outputs(address) do
    previous_summary_time = Archethic.BeaconChain.previous_summary_time(DateTime.utc_now())

    nodes =
      address
      |> Election.storage_nodes(P2P.authorized_and_available_nodes())
      |> Election.get_synchronized_nodes_before(previous_summary_time)

    address
    |> TransactionChain.fetch_unspent_outputs(nodes)
    |> Enum.to_list()
    |> Context.filter_inputs()
  end
end
