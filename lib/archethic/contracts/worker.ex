defmodule Archethic.Contracts.Worker do
  @moduledoc false

  alias Archethic.Account

  alias Archethic.ContractRegistry
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.ContractConditions, as: Conditions
  alias Archethic.Contracts.ContractConstants, as: Constants
  alias Archethic.Contracts.ActionInterpreter
  alias Archethic.Contracts.ConditionInterpreter

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
  alias Archethic.TransactionChain.TransactionData.Ownership

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.Utils
  alias Archethic.Utils.DetectNodeResponsiveness

  @extended_mode? Mix.env() != :prod

  require Logger

  use GenServer
  @vsn Mix.Project.config()[:version]

  def start_link(contract = %Contract{constants: %Constants{contract: constants}}) do
    GenServer.start_link(__MODULE__, contract, name: via_tuple(Map.get(constants, "address")))
  end

  @doc """
  Execute a transaction in the context of the contract.

  If the condition are respected a new transaction will be initiated
  """
  @spec execute(binary(), Transaction.t()) ::
          :ok | {:error, :no_transaction_trigger} | {:error, :condition_not_respected}
  def execute(address, tx = %Transaction{}) do
    GenServer.cast(via_tuple(address), {:execute, tx})
  end

  def init(contract = %Contract{}) do
    # Set trap_exit globally for the process
    Process.flag(:trap_exit, true)
    {:ok, %{contract: contract}, {:continue, :start_schedulers}}
  end

  def handle_continue(:start_schedulers, state = %{contract: %Contract{triggers: triggers}}) do
    new_state =
      Enum.reduce(triggers, state, fn {trigger_type, _}, acc ->
        case schedule_trigger(trigger_type) do
          timer when is_reference(timer) ->
            Map.update(acc, :timers, %{trigger_type => timer}, &Map.put(&1, trigger_type, timer))

          _ ->
            acc
        end
      end)

    {:noreply, new_state}
  end

  def handle_cast(
        {:execute, incoming_tx = %Transaction{}},
        state = %{
          contract: %Contract{
            triggers: triggers,
            constants: %Constants{
              contract: contract_constants = %{"address" => contract_address}
            },
            conditions: %{transaction: transaction_condition}
          }
        }
      ) do
    Logger.info("Execute contract transaction actions",
      transaction_address: Base.encode16(incoming_tx.address),
      transaction_type: incoming_tx.type,
      contract: Base.encode16(contract_address)
    )

    if Map.has_key?(triggers, :transaction) do
      constants = %{
        "contract" => contract_constants,
        "transaction" => Constants.from_transaction(incoming_tx)
      }

      contract_transaction = Constants.to_transaction(contract_constants)

      with true <- ConditionInterpreter.valid_conditions?(transaction_condition, constants),
           next_tx <- ActionInterpreter.execute(Map.fetch!(triggers, :transaction), constants),
           {:ok, next_tx} <- chain_transaction(next_tx, contract_transaction) do
        handle_new_transaction(next_tx)
        {:noreply, state}
      else
        false ->
          Logger.debug("Incoming transaction didn't match the condition",
            transaction_address: Base.encode16(incoming_tx.address),
            transaction_type: incoming_tx.type,
            contract: Base.encode16(contract_address)
          )

          {:noreply, state}

        {:error, :transaction_seed_decryption} ->
          {:noreply, state}
      end
    else
      Logger.debug("No transaction trigger",
        transaction_address: Base.encode16(incoming_tx.address),
        transaction_type: incoming_tx.type,
        contract: Base.encode16(contract_address)
      )

      {:noreply, state}
    end
  end

  def handle_info(
        {:trigger, {:datetime, timestamp}},
        state = %{
          contract: %Contract{
            triggers: triggers,
            constants: %Constants{contract: contract_constants = %{"address" => address}}
          }
        }
      ) do
    Logger.info("Execute contract datetime trigger actions",
      contract: Base.encode16(address)
    )

    constants = %{
      "contract" => contract_constants
    }

    contract_tx = Constants.to_transaction(contract_constants)

    with next_tx <-
           ActionInterpreter.execute(Map.fetch!(triggers, {:datetime, timestamp}), constants),
         {:ok, next_tx} <- chain_transaction(next_tx, contract_tx) do
      handle_new_transaction(next_tx)
    end

    {:noreply, Map.update!(state, :timers, &Map.delete(&1, {:datetime, timestamp}))}
  end

  def handle_info(
        {:trigger, {:interval, interval}},
        state = %{
          contract: %Contract{
            triggers: triggers,
            constants: %Constants{
              contract: contract_constants = %{"address" => address}
            }
          }
        }
      ) do
    Logger.info("Execute contract interval trigger actions",
      contract: Base.encode16(address)
    )

    # Schedule the next interval trigger
    interval_timer = schedule_trigger({:interval, interval})

    constants = %{
      "contract" => contract_constants
    }

    contract_transaction = Constants.to_transaction(contract_constants)

    with true <- enough_funds?(address),
         next_tx <-
           ActionInterpreter.execute(Map.fetch!(triggers, {:interval, interval}), constants),
         {:ok, next_tx} <- chain_transaction(next_tx, contract_transaction),
         :ok <- ensure_enough_funds(next_tx, address) do
      handle_new_transaction(next_tx)
    end

    {:noreply, put_in(state, [:timers, :interval], interval_timer)}
  end

  def handle_info(
        {:new_transaction, tx_address, :oracle, _timestamp},
        state = %{
          contract: %Contract{
            triggers: triggers,
            constants: %Constants{contract: contract_constants = %{"address" => address}},
            conditions: %{oracle: oracle_condition}
          }
        }
      ) do
    Logger.info("Execute contract oracle trigger actions", contract: Base.encode16(address))

    with true <- enough_funds?(address),
         true <- Map.has_key?(triggers, :oracle) do
      {:ok, tx} = TransactionChain.get_transaction(tx_address)

      constants = %{
        "contract" => contract_constants,
        "transaction" => Constants.from_transaction(tx)
      }

      contract_transaction = Constants.to_transaction(contract_constants)

      if Conditions.empty?(oracle_condition) do
        with next_tx <- ActionInterpreter.execute(Map.fetch!(triggers, :oracle), constants),
             {:ok, next_tx} <- chain_transaction(next_tx, contract_transaction),
             :ok <- ensure_enough_funds(next_tx, address) do
          handle_new_transaction(next_tx)
        end
      else
        with true <- ConditionInterpreter.valid_conditions?(oracle_condition, constants),
             next_tx <- ActionInterpreter.execute(Map.fetch!(triggers, :oracle), constants),
             {:ok, next_tx} <- chain_transaction(next_tx, contract_transaction),
             :ok <- ensure_enough_funds(next_tx, address) do
          handle_new_transaction(next_tx)
        else
          false ->
            Logger.error("Invalid oracle conditions", contract: Base.encode16(address))

          {:error, e} ->
            Logger.error("#{inspect(e)}", contract: Base.encode16(address))
        end
      end
    end

    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, _}, state) do
    {:noreply, state}
  end

  defp via_tuple(address) do
    {:via, Registry, {ContractRegistry, address}}
  end

  defp schedule_trigger(trigger = {:interval, interval}) do
    Process.send_after(
      self(),
      {:trigger, trigger},
      Utils.time_offset(interval, DateTime.utc_now(), @extended_mode?) * 1000
    )
  end

  defp schedule_trigger(trigger = {:datetime, datetime = %DateTime{}}) do
    seconds = DateTime.diff(datetime, DateTime.utc_now())

    if seconds > 0 do
      Process.send_after(self(), {:trigger, trigger}, seconds * 1000)
    end
  end

  defp schedule_trigger(:oracle) do
    PubSub.register_to_new_transaction_by_type(:oracle)
  end

  defp schedule_trigger(_), do: :ok

  defp handle_new_transaction(next_transaction = %Transaction{}) do
    validation_nodes = get_validation_nodes(next_transaction)

    # The first storage node of the contract initiate the sending of the new transaction
    if trigger_node?(validation_nodes) do
      Archethic.send_new_transaction(next_transaction)
    else
      DetectNodeResponsiveness.start_link(
        next_transaction.address,
        length(validation_nodes),
        fn count ->
          Logger.info("contract transaction ...attempt #{count}")

          if trigger_node?(validation_nodes, count) do
            Archethic.send_new_transaction(next_transaction)
          end
        end
      )
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
         next_tx,
         prev_tx = %Transaction{
           address: address,
           previous_public_key: previous_public_key
         }
       ) do
    %{next_transaction: %Transaction{type: new_type, data: new_data}} =
      %{next_transaction: next_tx, previous_transaction: prev_tx}
      |> chain_type()
      |> chain_code()
      |> chain_ownerships()

    case get_transaction_seed(prev_tx) do
      {:ok, transaction_seed} ->
        length = TransactionChain.size(address)

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
        {:error, :transaction_seed_decryption}
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

  defp chain_type(
         acc = %{
           next_transaction: %Transaction{type: nil},
           previous_transaction: _
         }
       ) do
    put_in(acc, [:next_transaction, Access.key(:type)], :contract)
  end

  defp chain_type(acc), do: acc

  defp chain_code(
         acc = %{
           next_transaction: %Transaction{data: %TransactionData{code: ""}},
           previous_transaction: %Transaction{data: %TransactionData{code: previous_code}}
         }
       ) do
    put_in(acc, [:next_transaction, Access.key(:data, %{}), Access.key(:code)], previous_code)
  end

  defp chain_code(acc), do: acc

  defp chain_ownerships(
         acc = %{
           next_transaction: %Transaction{data: %TransactionData{ownerships: []}},
           previous_transaction: %Transaction{
             data: %TransactionData{ownerships: previous_ownerships}
           }
         }
       ) do
    put_in(
      acc,
      [:next_transaction, Access.key(:data, %{}), Access.key(:ownerships)],
      previous_ownerships
    )
  end

  defp chain_ownerships(acc), do: acc

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

             balance > t_amount
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
end
