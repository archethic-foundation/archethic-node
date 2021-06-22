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
  alias ArchEthic.TransactionChain.TransactionData.Keys

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
              constants: %Constants{contract: contract_constants},
              conditions: %{transaction: transaction_condition}
            }
        }
      ) do
    Logger.info("Execute contract transaction actions",
      transaction: "#{incoming_tx.type}@#{Base.encode16(incoming_tx.address)}",
      contract: Base.encode16(Keyword.get(contract_constants, :address))
    )

    if Enum.any?(triggers, &(&1.type == :transaction)) do
      constants = %{
        "contract" => contract_constants,
        "transaction" => Constants.from_transaction(incoming_tx)
      }

      if Interpreter.valid_conditions?(transaction_condition, constants) do
        contract
        |> Interpreter.execute_actions(:transaction, constants)
        |> chain_transaction()
        |> handle_new_transaction()

        {:reply, :ok, state}
      else
        {:reply, {:error, :invalid_condition}, state}
      end
    else
      {:reply, {:error, :no_transaction_trigger}, state}
    end
  end

  def handle_info(
        %Trigger{type: :datetime},
        state = %{
          contract:
            contract = %Contract{
              constants: %Constants{contract: contract_constants}
            },
          timers: %{datetime: timer}
        }
      ) do
    Logger.info("Execute contract datetime trigger actions",
      contract: Base.encode16(Keyword.get(contract_constants, :address))
    )

    contract
    |> Interpreter.execute_actions(:datetime, contract_constants)
    |> chain_transaction()
    |> handle_new_transaction()

    Process.cancel_timer(timer)
    {:noreply, Map.update!(state, :timers, &Map.delete(&1, :datetime))}
  end

  def handle_info(
        trigger = %Trigger{type: :interval},
        state = %{
          contract:
            contract = %Contract{
              constants: %Constants{contract: contract_constants}
            }
        }
      ) do
    Logger.info("Execute contract interval trigger actions",
      contract: Base.encode16(Keyword.get(contract_constants, :address))
    )

    # Schedule the next interval trigger
    interval_timer = schedule_trigger(trigger)

    contract
    |> Interpreter.execute_actions(:interval, contract_constants)
    |> chain_transaction()
    |> handle_new_transaction()

    {:noreply, put_in(state, [:timers, :interval], interval_timer)}
  end

  def handle_info(
        {:new_transaction, tx_address, :oracle},
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
        |> chain_transaction()
        |> handle_new_transaction()

        {:noreply, state}
      else
        if Interpreter.valid_conditions?(oracle_condition, constants) do
          contract
          |> Interpreter.execute_actions(:oracle, constants)
          |> chain_transaction()
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

  defp handle_new_transaction({:ok, contract}), do: dispatch_transaction(contract)

  defp dispatch_transaction(%Contract{
         next_transaction: next_tx,
         constants: %Constants{contract: %{"address" => contract_address}}
       }) do
    [%Node{first_public_key: key} | _] = Replication.chain_storage_nodes(contract_address)

    # The first storage node of the contract initiate the sending of the new transaction
    # The contract must contains in the data authorized keys
    # the transaction seed encrypted with the storage nonce public key
    if key == Crypto.first_node_public_key() do
      validation_nodes = P2P.authorized_nodes()

      P2P.broadcast_message(validation_nodes, %StartMining{
        transaction: next_tx,
        validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key),
        welcome_node_public_key: Crypto.last_node_public_key()
      })
    end
  end

  defp chain_transaction(
         contract = %Contract{
           constants: %Constants{
             contract: %{
               "address" => address,
               "authorized_keys" => authorized_keys,
               "secret" => secret
             }
           }
         }
       ) do
    %Contract{next_transaction: %Transaction{type: new_type, data: new_data}} =
      contract
      |> chain_type()
      |> chain_code()
      |> chain_content()
      |> chain_secret()
      |> chain_authorized_keys()

    # TODO: improve transaction decryption and transaction signing to avoid the reveal of the transaction seed
    with encrypted_key <- Map.get(authorized_keys, Crypto.storage_nonce_public_key()),
         {:ok, aes_key} <- Crypto.ec_decrypt_with_storage_nonce(encrypted_key),
         {:ok, transaction_seed} <- Crypto.aes_decrypt(secret, aes_key),
         length <- TransactionChain.size(address) do
      {:ok,
       %{
         contract
         | next_transaction: Transaction.new(new_type, new_data, transaction_seed, length)
       }}
    end
  end

  defp chain_type(
         contract = %Contract{
           next_transaction: new_tx = %Transaction{type: nil},
           constants: %Constants{contract: %{"type" => previous_type}}
         }
       ) do
    new_tx = %{new_tx | type: previous_type}
    %{contract | next_transaction: new_tx}
  end

  defp chain_type(contract), do: contract

  defp chain_code(
         contract = %Contract{
           next_transaction: new_tx = %Transaction{data: %TransactionData{code: ""}},
           constants: %Constants{contract: %{"code" => previous_code}}
         }
       ) do
    new_tx = put_in(new_tx, [Access.key(:data, %{}), Access.key(:code)], previous_code)
    %{contract | next_transaction: new_tx}
  end

  defp chain_code(contract), do: contract

  defp chain_content(
         contract = %Contract{
           next_transaction: new_tx = %Transaction{data: %TransactionData{content: ""}},
           constants: %Constants{contract: %{"previous_content" => previous_content}}
         }
       ) do
    new_tx = put_in(new_tx, [Access.key(:data, %{}), Access.key(:content)], previous_content)
    %{contract | next_transaction: new_tx}
  end

  defp chain_content(contract), do: contract

  defp chain_secret(
         contract = %Contract{
           next_transaction:
             new_tx = %Transaction{data: %TransactionData{keys: %Keys{secret: ""}}},
           constants: %Constants{contract: %{"secret" => previous_secret}}
         }
       ) do
    new_tx =
      put_in(
        new_tx,
        [Access.key(:data, %{}), Access.key(:keys, %{}), Access.key(:secret)],
        previous_secret
      )

    %{contract | next_transaction: new_tx}
  end

  defp chain_secret(contract), do: contract

  defp chain_authorized_keys(
         contract = %Contract{
           next_transaction:
             new_tx = %Transaction{
               data: %TransactionData{keys: %Keys{authorized_keys: authorized_keys}}
             },
           constants: %Constants{contract: %{"authorized_keys" => previous_authorized_keys}}
         }
       )
       when map_size(authorized_keys) == 0 do
    new_tx =
      put_in(
        new_tx,
        [Access.key(:data, %{}), Access.key(:keys, %{}), Access.key(:authorized_keys)],
        previous_authorized_keys
      )

    %{contract | next_transaction: new_tx}
  end

  defp chain_authorized_keys(contract), do: contract
end
