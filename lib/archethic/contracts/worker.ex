defmodule Archethic.Contracts.Worker do
  @moduledoc false

  alias Archethic.ContractRegistry
  alias Archethic.Contracts
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Contract.ActionWithoutTransaction
  alias Archethic.Contracts.Contract.ActionWithTransaction
  alias Archethic.Contracts.Contract.Failure
  alias Archethic.Contracts.Loader
  alias Archethic.ContractSupervisor
  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.PubSub
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.Utils
  alias Archethic.Utils.DetectNodeResponsiveness

  @extended_mode? Mix.env() != :prod

  require Logger

  use GenServer
  @vsn 1

  def start_link(opts) do
    genesis_address = Keyword.fetch!(opts, :genesis_address)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(genesis_address))
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

  @doc """
  Return true if a worker exists for the genesis address
  """
  @spec exists?(genesis_address :: Crypto.prepended_hash()) :: boolean()
  def exists?(genesis_address),
    do: genesis_address |> via_tuple() |> GenServer.whereis() != nil

  @doc """
  Start a new worker for the genesis address
  """
  @spec new(genesis_address :: Crypto.prepended_hash(), contract :: Contract.t()) ::
          DynamicSupervisor.on_start_child()
  def new(genesis_address, contract) do
    DynamicSupervisor.start_child(
      ContractSupervisor,
      {__MODULE__, contract: contract, genesis_address: genesis_address}
    )
  end

  @doc """
  Stop a worker for the genesis address
  """
  @spec stop(genesis_address :: Crypto.prepended_hash()) :: :ok | {:error, :not_found}
  def stop(genesis_address) do
    case genesis_address |> via_tuple() |> GenServer.whereis() do
      nil ->
        :ok

      pid ->
        Logger.info("Stop smart contract at #{Base.encode16(genesis_address)}")
        DynamicSupervisor.terminate_child(ContractSupervisor, pid)
    end
  end

  @doc """
  Set a new contract version in the worker
  """
  @spec set_contract(genesis_address :: Crypto.prepended_hash(), contract :: Contract.t()) :: :ok
  def set_contract(genesis_address, contract) do
    genesis_address |> via_tuple() |> GenServer.cast({:new_contract, contract})
  end

  def init(opts) do
    # Set trap_exit globally for the process
    Process.flag(:trap_exit, true)

    PubSub.register_to_node_status()

    contract = Keyword.fetch!(opts, :contract)
    genesis_address = Keyword.fetch!(opts, :genesis_address)

    state = %{contract: contract, genesis_address: genesis_address}

    if Archethic.up?(), do: {:ok, state, {:continue, :start_schedulers}}, else: {:ok, state}
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

    {:noreply, new_state, {:continue, :process_next_call}}
  end

  def handle_continue(
        :process_next_call,
        state = %{contract: contract, genesis_address: genesis_address}
      ) do
    # Take next call to process
    with {trigger_tx, recipient} <- Loader.get_next_call(genesis_address),
         :ok <- Loader.request_worker_lock(genesis_address) do
      %Transaction{address: address, type: type} = trigger_tx

      Logger.info(
        "Execute transaction on contract #{Base.encode16(genesis_address)}",
        transaction_address: Base.encode16(address),
        transaction_type: type
      )

      trigger = Contract.get_trigger_for_recipient(recipient)

      execute_contract(contract, trigger, trigger_tx, recipient, genesis_address)
    end

    {:noreply, state}
  end

  def handle_cast({:new_contract, contract}, state = %{genesis_address: genesis_address}) do
    new_state = state |> cancel_schedulers() |> Map.put(:contract, contract)

    Loader.unlock_worker(genesis_address)

    if Archethic.up?(),
      do: {:noreply, new_state, {:continue, :start_schedulers}},
      else: {:noreply, new_state}
  end

  # TRIGGER: TRANSACTION
  def handle_cast(
        {:execute, trigger_tx = %Transaction{address: address, type: type},
         recipient = %Recipient{}},
        state = %{contract: contract, genesis_address: genesis_address}
      ) do
    Logger.info(
      "Execute transaction on contract #{Base.encode16(genesis_address)}",
      transaction_address: Base.encode16(address),
      transaction_type: type
    )

    trigger = Contract.get_trigger_for_recipient(recipient)

    execute_contract(contract, trigger, trigger_tx, recipient, genesis_address)

    {:noreply, state}
  end

  # TRIGGER: DATETIME
  def handle_info(
        {:trigger, trigger_type = {:datetime, _}},
        state = %{contract: contract, genesis_address: genesis_address}
      ) do
    execute_contract(contract, trigger_type, nil, nil, genesis_address)

    {:noreply, Map.update!(state, :timers, &Map.delete(&1, trigger_type))}
  end

  # TRIGGER: INTERVAL
  def handle_info(
        {:trigger, trigger_type = {:interval, interval}},
        state = %{
          contract: contract = %Contract{triggers: triggers},
          genesis_address: genesis_address
        }
      ) do
    execute_contract(contract, trigger_type, nil, nil, genesis_address)

    interval_timer = schedule_trigger({:interval, interval}, Map.keys(triggers))
    {:noreply, put_in(state, [:timers, :interval], interval_timer)}
  end

  # TRIGGER: ORACLE
  def handle_info(
        {:new_transaction, tx_address, :oracle, _timestamp},
        state = %{contract: contract, genesis_address: genesis_address}
      ) do
    trigger_datetime = DateTime.utc_now()
    {:ok, oracle_tx} = TransactionChain.get_transaction(tx_address)

    case Contracts.execute_condition(:oracle, contract, oracle_tx, nil, trigger_datetime) do
      {:ok, _logs} ->
        execute_contract(contract, :oracle, oracle_tx, nil, genesis_address)

      _ ->
        :skip
    end

    {:noreply, state}
  end

  # Node is up, starting schedulers
  def handle_info(:node_up, state), do: {:noreply, state, {:continue, :start_schedulers}}

  # Node is down, stoping schedulers
  def handle_info(:node_down, state), do: {:noreply, cancel_schedulers(state)}

  # Node responsiveness timeout
  def handle_info({:EXIT, _pid, _}, state = %{genesis_address: genesis_address}) do
    Loader.unlock_worker(genesis_address)
    {:noreply, state, {:continue, :process_next_call}}
  end

  def code_change(old_version, state = %{contract: %Contract{transaction: contract_tx}}, _) do
    Logger.debug("CODE_CHANGE #{old_version} for Contracts.Worker #{inspect(self())}")
    # because the worker maintain a parsed contract in memory
    # it's possible that the parsing changed with the new release
    # so we reparse the contract here
    {:ok, %{state | contract: Contract.from_transaction!(contract_tx)}}
  end

  def terminate(_, %{genesis_address: genesis_address}), do: Loader.unlock_worker(genesis_address)

  # ----------------------------------------------
  defp via_tuple(address) do
    {:via, Registry, {ContractRegistry, address}}
  end

  defp execute_contract(
         contract = %Contract{transaction: %Transaction{address: contract_address}},
         trigger,
         maybe_trigger_tx,
         maybe_recipient,
         contract_genesis_address
       ) do
    meta = log_metadata(contract_address, maybe_trigger_tx)
    Logger.debug("Contract execution started (trigger=#{inspect(trigger)})", meta)

    with {:ok, %ActionWithTransaction{next_tx: next_tx}} <-
           Contracts.execute_trigger(trigger, contract, maybe_trigger_tx, maybe_recipient),
         index = TransactionChain.get_size(contract_address),
         {:ok, next_tx} <- Contract.sign_next_transaction(contract, next_tx, index),
         contract_context <-
           get_contract_context(trigger, maybe_trigger_tx, maybe_recipient),
         :ok <- send_transaction(contract_context, next_tx, contract_genesis_address) do
      Logger.debug("Contract execution success", meta)
    else
      {:ok, %ActionWithoutTransaction{}} ->
        Logger.debug("Contract execution success but there is no new transaction", meta)

      {:error, %Failure{user_friendly_error: reason}} ->
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
end
