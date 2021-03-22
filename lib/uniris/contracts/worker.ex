defmodule Uniris.Contracts.Worker do
  @moduledoc false

  alias Uniris.ContractRegistry
  alias Uniris.Contracts.Contract
  alias Uniris.Contracts.Contract.Conditions
  alias Uniris.Contracts.Contract.Constants
  alias Uniris.Contracts.Contract.Trigger
  alias Uniris.Contracts.Interpreter

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.StartMining
  alias Uniris.P2P.Node

  alias Uniris.Replication

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Keys

  alias Uniris.Utils

  require Logger

  use GenServer

  def start_link(contract = %Contract{constants: %Constants{contract: constants}}) do
    GenServer.start_link(__MODULE__, contract, name: via_tuple(Keyword.get(constants, :address)))
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
    Enum.each(triggers, &schedule_trigger(self(), &1))
    {:ok, %{contract: contract}}
  end

  def handle_call(
        {:execute, incoming_tx = %Transaction{}},
        _from,
        state = %{
          contract:
            contract = %Contract{
              triggers: triggers,
              constants: %Constants{contract: contract_constants},
              conditions: %Conditions{transaction: transaction_condition}
            }
        }
      ) do
    Logger.info("Execute contract transaction actions",
      transaction: Base.encode16(incoming_tx.address),
      contract: Base.encode16(Keyword.get(contract_constants, :address))
    )

    case Enum.find(triggers, &(&1.type == :transaction)) do
      nil ->
        Logger.info("No transaction trigger for this contract")
        {:reply, {:error, :no_transaction_trigger}, state}

      %Trigger{} ->
        incoming_transaction_constants = Constants.from_transaction(incoming_tx)

        constants = Keyword.merge([contract: contract_constants], incoming_transaction_constants)

        stringified_transaction_condition =
          case transaction_condition do
            nil ->
              ""

            _ ->
              Macro.to_string(transaction_condition)
          end

        if Interpreter.can_execute?(stringified_transaction_condition, constants) do
          constants = [transaction: incoming_transaction_constants, contract: contract_constants]

          Task.start(fn ->
            contract
            |> Interpreter.execute_actions(:transaction, constants)
            |> chain_transaction()
            |> handle_new_transaction()
          end)

          {:reply, :ok, state}
        else
          {:reply, {:error, :invalid_condition}, state}
        end
    end
  end

  def handle_info(
        %Trigger{type: :datetime},
        state = %{
          contract:
            contract = %Contract{
              constants: %Constants{contract: contract_constants}
            }
        }
      ) do
    Logger.info("Execute contract datetime trigger actions",
      contract: Base.encode16(Keyword.get(contract_constants, :address))
    )

    Task.start(fn ->
      contract
      |> Interpreter.execute_actions(:datetime, contract_constants)
      |> chain_transaction()
      |> handle_new_transaction()
    end)

    {:noreply, state}
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
    pid = self()
    Task.start(fn -> schedule_trigger(pid, trigger) end)

    Task.start(fn ->
      contract
      |> Interpreter.execute_actions(:interval, contract_constants)
      |> chain_transaction()
      |> handle_new_transaction()
    end)

    {:noreply, state}
  end

  defp via_tuple(address) do
    {:via, Registry, {ContractRegistry, address}}
  end

  defp schedule_trigger(pid, trigger = %Trigger{type: :interval, opts: [at: interval]}) do
    Process.send_after(pid, trigger, Utils.time_offset(interval) * 1000)
  end

  defp schedule_trigger(
         pid,
         trigger = %Trigger{type: :datetime, opts: [at: datetime = %DateTime{}]}
       ) do
    seconds = DateTime.diff(datetime, DateTime.utc_now())
    Process.send_after(pid, trigger, seconds * 1000)
  end

  defp schedule_trigger(_, _), do: :ok

  defp handle_new_transaction(e = {:error, _}) do
    Logger.error("#{inspect(e)}")
  end

  defp handle_new_transaction({:ok, contract}), do: dispatch_transaction(contract)

  defp dispatch_transaction(%Contract{
         next_transaction: next_tx,
         constants: %Constants{contract: contract_constants}
       }) do
    contract_address = Keyword.get(contract_constants, :address)

    [%Node{first_public_key: key}] =
      Replication.chain_storage_nodes(contract_address, P2P.list_nodes(availability: :global))

    # The first storage node of the contract initiate the sending of the new transaction
    # The contract must contains in the data authorized keys
    # the transaction seed encrypted with the storage nonce public key
    if key == Crypto.node_public_key(0) do
      validation_nodes = P2P.list_nodes(authorized?: true, availability: :global)

      validation_nodes
      |> P2P.broadcast_message(%StartMining{
        transaction: next_tx,
        validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key),
        welcome_node_public_key: Crypto.node_public_key()
      })
    end
  end

  defp chain_transaction(
         contract = %Contract{
           constants: %Constants{contract: contract_constants}
         }
       ) do
    address = Keyword.get(contract_constants, :address)
    authorized_keys = Keyword.get(contract_constants, :authorized_keys)
    secret = Keyword.get(contract_constants, :secret)

    %Contract{next_transaction: %Transaction{type: new_type, data: new_data}} =
      contract
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

  defp chain_code(
         contract = %Contract{
           next_transaction: new_tx = %Transaction{data: %TransactionData{code: new_code}},
           constants: %Constants{contract: contract_constants}
         }
       ) do
    case new_code do
      "" ->
        previous_code = Keyword.get(contract_constants, :code, "")
        new_tx = put_in(new_tx, [Access.key(:data, %{}), Access.key(:code)], previous_code)
        %{contract | next_transaction: new_tx}

      _ ->
        contract
    end
  end

  defp chain_content(
         contract = %Contract{
           next_transaction: new_tx = %Transaction{data: %TransactionData{content: content}},
           constants: %Constants{contract: contract_constants}
         }
       )
       when is_list(contract_constants) do
    case content do
      "" ->
        previous_content = Keyword.get(contract_constants, :content, "")
        new_tx = put_in(new_tx, [Access.key(:data, %{}), Access.key(:content)], previous_content)
        %{contract | next_transaction: new_tx}

      _ ->
        contract
    end
  end

  defp chain_secret(
         contract = %Contract{
           next_transaction:
             new_tx = %Transaction{data: %TransactionData{keys: %Keys{secret: secret}}},
           constants: %Constants{contract: contract_constants}
         }
       )
       when is_list(contract_constants) do
    case secret do
      "" ->
        previous_secret = Keyword.get(contract_constants, :secret, "")

        new_tx =
          put_in(
            new_tx,
            [Access.key(:data, %{}), Access.key(:keys, %{}), Access.key(:secret)],
            previous_secret
          )

        %{contract | next_transaction: new_tx}

      _ ->
        contract
    end
  end

  defp chain_authorized_keys(
         contract = %Contract{
           next_transaction:
             new_tx = %Transaction{
               data: %TransactionData{keys: %Keys{authorized_keys: authorized_keys}}
             },
           constants: %Constants{contract: contract_constants}
         }
       )
       when is_list(contract_constants) do
    if map_size(authorized_keys) == 0 do
      previous_authorized_keys = Keyword.get(contract_constants, :authorized_keys, %{})

      new_tx =
        put_in(
          new_tx,
          [Access.key(:data, %{}), Access.key(:keys, %{}), Access.key(:authorized_keys)],
          previous_authorized_keys
        )

      %{contract | next_transaction: new_tx}
    else
      contract
    end
  end
end
