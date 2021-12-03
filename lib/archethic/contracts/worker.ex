defmodule ArchEthic.Contracts.Worker do
  @moduledoc false

  alias ArchEthic.Account

  alias ArchEthic.ContractRegistry
  alias ArchEthic.Contracts.Contract
  alias ArchEthic.Contracts.Contract.Conditions
  alias ArchEthic.Contracts.Contract.Constants
  alias ArchEthic.Contracts.Contract.Trigger
  alias ArchEthic.Contracts.Interpreter

  alias ArchEthic.Crypto

  alias ArchEthic.Mining

  alias ArchEthic.OracleChain

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.StartMining
  alias ArchEthic.P2P.Node

  alias ArchEthic.PubSub

  alias ArchEthic.Replication

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ownership

  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

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

      contract_transaction = Constants.to_transaction(contract_constants)

      with true <- Interpreter.valid_conditions?(transaction_condition, constants),
           next_tx <- Interpreter.execute_actions(contract, :transaction, constants),
           {:ok, next_tx} <- chain_transaction(next_tx, contract_transaction) do
        handle_new_transaction(next_tx)
        {:reply, :ok, state}
      else
        false ->
          Logger.debug("Incoming transaction didn't match the condition",
            transaction_address: Base.encode16(incoming_tx.address),
            transaction_type: incoming_tx.type,
            contract: Base.encode16(contract_address)
          )

          {:reply, {:error, :invalid_condition}, state}

        {:error, :transaction_seed_decryption} ->
          {:reply, :error, state}
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

    contract_tx = Constants.to_transaction(contract_constants)

    with next_tx <- Interpreter.execute_actions(contract, :datetime, constants),
         {:ok, next_tx} <- chain_transaction(next_tx, contract_tx) do
      handle_new_transaction(next_tx)
    end

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

    contract_transaction = Constants.to_transaction(contract_constants)

    with true <- enough_funds?(address),
         next_tx <- Interpreter.execute_actions(contract, :interval, constants),
         {:ok, next_tx} <- chain_transaction(next_tx, contract_transaction),
         :ok <- ensure_enough_funds(next_tx, address) do
      handle_new_transaction(next_tx)
    end

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

    with true <- enough_funds?(address),
         true <- Enum.any?(triggers, &(&1.type == :oracle)) do
      {:ok, tx} = TransactionChain.get_transaction(tx_address)

      constants = %{
        "contract" => contract_constants,
        "transaction" => Constants.from_transaction(tx)
      }

      contract_transaction = Constants.to_transaction(contract_constants)

      if Conditions.empty?(oracle_condition) do
        with next_tx <- Interpreter.execute_actions(contract, :oracle, constants),
             {:ok, next_tx} <- chain_transaction(next_tx, contract_transaction),
             :ok <- ensure_enough_funds(next_tx, address) do
          handle_new_transaction(next_tx)
        end
      else
        with true <- Interpreter.valid_conditions?(oracle_condition, constants),
             next_tx <- Interpreter.execute_actions(contract, :oracle, constants),
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

  defp handle_new_transaction(next_transaction = %Transaction{}) do
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

  defp enough_funds?(contract_address) do
    case Account.get_balance(contract_address) do
      %{uco: uco_balance} when uco_balance > 0 ->
        true

<<<<<<< Updated upstream
  defp ensure_enough_funds({:error, _} = e, _), do: e
=======
      _ ->
        Logger.debug("Not enough funds to interpret the smart contract for a trigger interval",
          contract: Base.encode16(contract_address)
        )
>>>>>>> Stashed changes

        false
    end
  end

  defp ensure_enough_funds(next_transaction, contract_address) do
    %{uco: uco_to_transfer, nft: nft_to_transfer} =
      next_transaction
      |> Transaction.get_movements()
      |> Enum.reduce(%{uco: 0, nft: %{}}, fn
        %TransactionMovement{type: :UCO, amount: amount}, acc ->
          Map.update!(acc, :uco, &(&1 + amount))

        %TransactionMovement{type: {:NFT, nft_address}, amount: amount}, acc ->
          Map.update!(acc, :nft, &Map.put(&1, nft_address, amount))
      end)

    %{uco: uco_balance, nft: nft_balances} = Account.get_balance(contract_address)

    uco_usd_price =
      DateTime.utc_now()
      |> OracleChain.get_uco_price()
      |> Keyword.get(:usd)

    tx_fee =
      Mining.get_transaction_fee(
        next_transaction,
        uco_usd_price
      )

    with true <- uco_balance > uco_to_transfer + tx_fee,
         true <-
           Enum.all?(nft_to_transfer, fn {nft_address, amount} ->
             %{amount: balance} = Enum.find(nft_balances, &(Map.get(&1, :nft) == nft_address))
             balance > amount
           end) do
      :ok
    else
      false ->
        Logger.debug(
          "Not enough funds to submit the transaction - expected %{ UCO: #{uco_to_transfer + tx_fee},  nft: #{inspect(nft_to_transfer)}} - got: %{ UCO: #{uco_balance}, nft: #{inspect(nft_balances)}}",
          contract: Base.encode16(contract_address)
        )

        {:error, :not_enough_funds}
    end
  end
end
