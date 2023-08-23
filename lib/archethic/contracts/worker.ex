defmodule Archethic.Contracts.Worker do
  @moduledoc false

  alias Archethic.Account

  alias Archethic.ContractRegistry
  alias Archethic.Contracts
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.ContractConstants, as: Constants

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.Mining

  alias Archethic.OracleChain

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.PubSub

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.TransactionData.Ownership

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.Utils
  alias Archethic.Utils.DetectNodeResponsiveness

  alias Crontab.CronExpression.Parser, as: CronParser

  @extended_mode? Mix.env() != :prod

  require Logger

  use GenServer
  @vsn Mix.Project.config()[:version]

  def start_link(contract = %Contract{constants: %Constants{contract: constants}}) do
    GenServer.start_link(__MODULE__, contract, name: via_tuple(Map.get(constants, "address")))
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
  def handle_cast(
        {
          :execute,
          trigger_tx = %Transaction{address: trigger_tx_address},
          recipient = %Recipient{}
        },
        state = %{contract: contract}
      ) do
    contract_tx =
      %Transaction{address: contract_address} =
      Constants.to_transaction(contract.constants.contract)

    trigger_datetime = DateTime.utc_now()
    meta = log_metadata(contract_address, trigger_tx)
    Logger.debug("Contract execution started (trigger=transaction)", meta)

    trigger = Contract.get_trigger_for_recipient(contract, recipient)

    with true <- enough_funds?(contract_address),
         {:ok, next_tx = %Transaction{}} <-
           Contracts.execute_trigger(
             trigger,
             contract,
             trigger_tx,
             recipient
           ),
         {:ok, next_tx} <- chain_transaction(next_tx, contract_tx),
         :ok <- ensure_enough_funds(next_tx, contract_address),
         :ok <-
           handle_new_transaction(
             {:transaction, trigger_tx_address, recipient},
             next_tx,
             trigger_datetime
           ) do
      Logger.debug("Contract execution success", meta)
    else
      {:ok, nil} ->
        Logger.debug("Contract execution success but there is no new transaction", meta)

      _ ->
        Logger.debug("Contract execution failed", meta)
    end

    {:noreply, state}
  end

  # TRIGGER: DATETIME
  def handle_info(
        {:trigger, trigger_type = {:datetime, _}},
        state = %{contract: contract}
      ) do
    contract_tx =
      %Transaction{address: contract_address} =
      Constants.to_transaction(contract.constants.contract)

    trigger_datetime = DateTime.utc_now()
    meta = log_metadata(contract_address)
    Logger.debug("Contract execution started (trigger=datetime)", meta)

    with true <- enough_funds?(contract_address),
         {:ok, next_tx = %Transaction{}} <-
           Contracts.execute_trigger(trigger_type, contract, nil, nil),
         {:ok, next_tx} <- chain_transaction(next_tx, contract_tx),
         :ok <- ensure_enough_funds(next_tx, contract_address),
         :ok <- handle_new_transaction(trigger_type, next_tx, trigger_datetime) do
      Logger.debug("Contract execution success", meta)
    else
      {:ok, nil} ->
        Logger.debug("Contract execution success but there is no new transaction", meta)

      _ ->
        Logger.debug("Contract execution failed", meta)
    end

    {:noreply, Map.update!(state, :timers, &Map.delete(&1, trigger_type))}
  end

  # TRIGGER: INTERVAL
  def handle_info(
        {:trigger, trigger_type = {:interval, interval}},
        state = %{contract: contract = %Contract{triggers: triggers}}
      ) do
    contract_tx =
      %Transaction{address: contract_address} =
      Constants.to_transaction(contract.constants.contract)

    trigger_datetime = DateTime.utc_now()
    meta = log_metadata(contract_address)
    Logger.debug("Contract execution started (trigger=interval)", meta)

    interval_datetime = Utils.get_current_time_for_interval(interval)

    with true <- enough_funds?(contract_address),
         {:ok, next_tx = %Transaction{}} <-
           Contracts.execute_trigger(trigger_type, contract, nil, nil),
         {:ok, next_tx} <- chain_transaction(next_tx, contract_tx),
         :ok <- ensure_enough_funds(next_tx, contract_address),
         :ok <-
           handle_new_transaction(
             {:interval, interval, interval_datetime},
             next_tx,
             trigger_datetime
           ) do
      Logger.debug("Contract execution success", meta)
    else
      {:ok, nil} ->
        Logger.debug("Contract execution success but there is no new transaction", meta)

      _ ->
        Logger.debug("Contract execution failed", meta)
    end

    interval_timer = schedule_trigger({:interval, interval}, Map.keys(triggers))
    {:noreply, put_in(state, [:timers, :interval], interval_timer)}
  end

  # TRIGGER: ORACLE
  def handle_info(
        {:new_transaction, tx_address, :oracle, _timestamp},
        state = %{contract: contract}
      ) do
    contract_tx =
      %Transaction{address: contract_address} =
      Constants.to_transaction(contract.constants.contract)

    trigger_datetime = DateTime.utc_now()
    {:ok, oracle_tx} = TransactionChain.get_transaction(tx_address)

    if Contracts.valid_condition?(:oracle, contract, oracle_tx, nil, trigger_datetime) do
      meta = log_metadata(contract_address, oracle_tx)
      Logger.debug("Contract execution started (trigger=oracle)", meta)

      with true <- enough_funds?(contract_address),
           {:ok, next_tx = %Transaction{}} <-
             Contracts.execute_trigger(:oracle, contract, oracle_tx, nil),
           {:ok, next_tx} <- chain_transaction(next_tx, contract_tx),
           :ok <- ensure_enough_funds(next_tx, contract_address),
           :ok <-
             handle_new_transaction({:oracle, tx_address}, next_tx, trigger_datetime) do
        Logger.debug("Contract execution success", meta)
      else
        {:ok, nil} ->
          Logger.debug("Contract execution success but there is no new transaction", meta)

        _ ->
          Logger.debug("Contract execution failed", meta)
      end
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

  defp schedule_trigger(trigger = {:interval, interval}, triggers_type) do
    now = DateTime.utc_now()

    next_tick =
      interval
      |> CronParser.parse!(@extended_mode?)
      |> Utils.next_date(now)

    # do not allow an interval trigger if there is a datetime trigger at same time
    # because one of them would get a "transaction is already mining"
    next_tick =
      if {:datetime, next_tick} in triggers_type do
        Logger.debug(
          "Contract scheduler skips next tick for trigger=interval because there is a trigger=datetime at the same time that takes precedence"
        )

        interval
        |> CronParser.parse!(@extended_mode?)
        |> Utils.next_date(next_tick)
      else
        next_tick
      end

    Process.send_after(
      self(),
      {:trigger, trigger},
      DateTime.diff(next_tick, now, :millisecond)
    )
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

  defp handle_new_transaction(
         trigger,
         next_transaction = %Transaction{},
         trigger_datetime
       ) do
    validation_nodes = get_validation_nodes(next_transaction)

    # In a next issue, we'll have different status such as :no_output and :failure
    contract_context = %Contract.Context{
      status: :tx_output,
      trigger: trigger,
      timestamp: trigger_datetime
    }

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
    %Node{first_public_key: key} =
      validation_nodes
      |> Enum.at(count)

    key == Crypto.first_node_public_key()
  end

  defp chain_transaction(
         _next_tx = %Transaction{
           type: new_type,
           data: new_data
         },
         prev_tx = %Transaction{
           address: address,
           previous_public_key: previous_public_key
         }
       ) do
    case get_transaction_seed(prev_tx) do
      {:ok, transaction_seed} ->
        length = TransactionChain.get_size(address)

        {:ok,
         Transaction.new(
           new_type,
           new_data,
           transaction_seed,
           length,
           Crypto.get_public_key_curve(previous_public_key)
         )}

      _ ->
        Logger.info("Cannot decrypt the transaction seed", contract: Base.encode16(address))
        :error
    end
  end

  defp get_transaction_seed(%Transaction{
         data: %TransactionData{ownerships: ownerships}
       }) do
    storage_nonce_public_key = Crypto.storage_nonce_public_key()

    %Ownership{secret: secret, authorized_keys: authorized_keys} =
      Enum.find(ownerships, &Ownership.authorized_public_key?(&1, storage_nonce_public_key))

    encrypted_key = Map.get(authorized_keys, storage_nonce_public_key)

    case Crypto.ec_decrypt_with_storage_nonce(encrypted_key) do
      {:ok, aes_key} ->
        Crypto.aes_decrypt(secret, aes_key)

      {:error, :decryption_failed} ->
        {:error, :decryption_failed}
    end
  end

  defp enough_funds?(contract_address) do
    case Account.get_balance(contract_address) do
      %{uco: uco_balance} when uco_balance > 0 ->
        true

      _ ->
        Logger.debug("Not enough funds to interpret the smart contract for a trigger interval",
          contract: Base.encode16(contract_address)
        )

        false
    end
  end

  defp ensure_enough_funds(next_transaction, contract_address) do
    %{uco: uco_to_transfer, token: token_to_transfer} =
      next_transaction
      |> Transaction.get_movements()
      |> Enum.reduce(%{uco: 0, token: %{}}, fn
        %TransactionMovement{type: :UCO, amount: amount}, acc ->
          Map.update!(acc, :uco, &(&1 + amount))

        %TransactionMovement{type: {:token, token_address, token_id}, amount: amount}, acc ->
          Map.update!(acc, :token, &Map.put(&1, {token_address, token_id}, amount))
      end)

    %{uco: uco_balance, token: token_balances} = Account.get_balance(contract_address)

    timestamp = DateTime.utc_now()

    uco_usd_price =
      timestamp
      |> OracleChain.get_uco_price()
      |> Keyword.get(:usd)

    tx_fee =
      Mining.get_transaction_fee(
        next_transaction,
        uco_usd_price,
        timestamp
      )

    with true <- uco_balance > uco_to_transfer + tx_fee,
         true <-
           Enum.all?(token_to_transfer, fn {{t_token_address, t_token_id}, t_amount} ->
             {{_token_address, _token_id}, balance} =
               Enum.find(token_balances, fn {{f_token_address, f_token_id}, _f_amount} ->
                 f_token_address == t_token_address and f_token_id == t_token_id
               end)

             balance >= t_amount
           end) do
      :ok
    else
      false ->
        Logger.debug(
          "Not enough funds to submit the transaction - expected %{ UCO: #{uco_to_transfer + tx_fee},  token: #{inspect(token_to_transfer)}} - got: %{ UCO: #{uco_balance}, token: #{inspect(token_balances)}}",
          contract: Base.encode16(contract_address)
        )

        {:error, :not_enough_funds}
    end
  end

  defp log_metadata(contract_address), do: log_metadata(contract_address, nil)

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
