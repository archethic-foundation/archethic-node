defmodule ArchEthic.Contracts.Worker do
  @moduledoc false

  # TODO: should process functions only if there is funds (for the prepaid default option)

  alias ArchEthic.ContractRegistry
  alias ArchEthic.Contracts.Contract
  alias ArchEthic.Contracts.Contract.Conditions
  alias ArchEthic.Contracts.Contract.Constants
  alias ArchEthic.Contracts.Contract.Trigger
  alias ArchEthic.Contracts.Interpreter

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.StartMining
  alias ArchEthic.P2P.Node

  alias ArchEthic.PubSub

  alias ArchEthic.Replication

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ownership

  alias ArchEthic.Utils

  require Logger

  use GenServer

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
    GenServer.call(via_tuple(address), {:execute, tx})
  end

  def init(contract = %Contract{triggers: triggers}) do
    state =
      Enum.reduce(triggers, %{contract: contract}, fn trigger = %Trigger{type: type}, acc ->
        case schedule_trigger(trigger) do
          timer when is_reference(timer) ->
            Map.update(acc, :timers, %{type => timer}, &Map.put(&1, type, timer))

          _ ->
            acc
        end
      end)

    {:ok, state}
  end

  def handle_call(
        {:execute, incoming_tx = %Transaction{}},
        _from,
        state = %{
          contract:
            contract = %Contract{
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

    if Enum.any?(triggers, &(&1.type == :transaction)) do
      constants = %{
        "contract" => contract_constants,
        "transaction" => Constants.from_transaction(incoming_tx)
      }

      if Interpreter.valid_conditions?(transaction_condition, constants) do
        contract
        |> Interpreter.execute_actions(:transaction, constants)
        |> chain_transaction(Constants.to_transaction(contract_constants))
        |> handle_new_transaction()

        {:reply, :ok, state}
      else
        Logger.debug("Incoming transaction didn't match the condition",
          transaction_address: Base.encode16(incoming_tx.address),
          transaction_type: incoming_tx.type,
          contract: Base.encode16(contract_address)
        )

        {:reply, {:error, :invalid_condition}, state}
      end
    else
      Logger.debug("No transaction trigger",
        transaction_address: Base.encode16(incoming_tx.address),
        transaction_type: incoming_tx.type,
        contract: Base.encode16(contract_address)
      )

      {:reply, {:error, :no_transaction_trigger}, state}
    end
  end

  def handle_info(
        %Trigger{type: :datetime},
        state = %{
          contract:
            contract = %Contract{
              constants: %Constants{contract: contract_constants = %{"address" => address}}
            },
          timers: %{datetime: timer}
        }
      ) do
    Logger.info("Execute contract datetime trigger actions",
      contract: Base.encode16(address)
    )

    constants = %{
      "contract" => contract_constants
    }

    contract
    |> Interpreter.execute_actions(:datetime, constants)
    |> chain_transaction(Constants.to_transaction(contract_constants))
    |> handle_new_transaction()

    Process.cancel_timer(timer)
    {:noreply, Map.update!(state, :timers, &Map.delete(&1, :datetime))}
  end

  def handle_info(
        trigger = %Trigger{type: :interval},
        state = %{
          contract:
            contract = %Contract{
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
    interval_timer = schedule_trigger(trigger)

    constants = %{
      "contract" => contract_constants
    }

    contract
    |> Interpreter.execute_actions(:interval, constants)
    |> chain_transaction(Constants.to_transaction(contract_constants))
    |> handle_new_transaction()

    {:noreply, put_in(state, [:timers, :interval], interval_timer)}
  end

  def handle_info(
        {:new_transaction, tx_address, :oracle, _timestamp},
        state = %{
          contract:
            contract = %Contract{
              triggers: triggers,
              constants: %Constants{contract: contract_constants = %{"address" => address}},
              conditions: %{oracle: oracle_condition}
            }
        }
      ) do
    Logger.info("Execute contract oracle trigger actions", contract: Base.encode16(address))

    if Enum.any?(triggers, &(&1.type == :oracle)) do
      {:ok, tx} = TransactionChain.get_transaction(tx_address)

      constants = %{
        "contract" => contract_constants,
        "transaction" => Constants.from_transaction(tx)
      }

      if Conditions.empty?(oracle_condition) do
        contract
        |> Interpreter.execute_actions(:oracle, constants)
        |> chain_transaction(Constants.to_transaction(constants))
        |> handle_new_transaction()

        {:noreply, state}
      else
        if Interpreter.valid_conditions?(oracle_condition, constants) do
          contract
          |> Interpreter.execute_actions(:oracle, constants)
          |> chain_transaction(Constants.to_transaction(contract_constants))
          |> handle_new_transaction()

          {:noreply, state}
        else
          {:noreply, state}
        end
      end
    else
      {:noreply, state}
    end
  end

  defp via_tuple(address) do
    {:via, Registry, {ContractRegistry, address}}
  end

  defp schedule_trigger(trigger = %Trigger{type: :interval, opts: [at: interval]}) do
    Process.send_after(self(), trigger, Utils.time_offset(interval) * 1000)
  end

  defp schedule_trigger(trigger = %Trigger{type: :datetime, opts: [at: datetime = %DateTime{}]}) do
    seconds = DateTime.diff(datetime, DateTime.utc_now())
    Process.send_after(self(), trigger, seconds * 1000)
  end

  defp schedule_trigger(%Trigger{type: :oracle}) do
    PubSub.register_to_new_transaction_by_type(:oracle)
  end

  defp schedule_trigger(_), do: :ok

  defp handle_new_transaction(e = {:error, _}) do
    Logger.error("#{inspect(e)}")
  end

  defp handle_new_transaction({:ok, next_transaction = %Transaction{}}) do
    [%Node{first_public_key: key} | _] =
      next_transaction
      |> Transaction.previous_address()
      |> Replication.chain_storage_nodes()

    # The first storage node of the contract initiate the sending of the new transaction
    if key == Crypto.first_node_public_key() do
      validation_nodes = P2P.authorized_nodes()

      P2P.broadcast_message(validation_nodes, %StartMining{
        transaction: next_transaction,
        validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key),
        welcome_node_public_key: Crypto.last_node_public_key()
      })
    end
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
      |> chain_content()
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
        Logger.error("Cannot decrypt the transaction seed", contract: Base.encode16(address))
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

    with {:ok, aes_key} <- Crypto.ec_decrypt_with_storage_nonce(encrypted_key),
         {:ok, transaction_seed} <- Crypto.aes_decrypt(secret, aes_key) do
      {:ok, transaction_seed}
    end
  end

  defp chain_type(
         acc = %{
           next_transaction: %Transaction{type: nil},
           previous_transaction: %Transaction{type: previous_type}
         }
       ) do
    put_in(acc, [:next_transaction, :type], previous_type)
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

  defp chain_content(
         acc = %{
           next_transaction: %Transaction{data: %TransactionData{content: ""}},
           previous_transaction: %Transaction{data: %TransactionData{content: previous_content}}
         }
       ) do
    put_in(
      acc,
      [:next_transaction, Access.key(:data, %{}), Access.key(:content)],
      previous_content
    )
  end

  defp chain_content(acc), do: acc

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
end
