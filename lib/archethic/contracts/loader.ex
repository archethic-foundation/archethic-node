defmodule Archethic.Contracts.Loader do
  @moduledoc false

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Worker

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient

  alias Archethic.UTXO

  require Logger

  use GenServer
  @vsn 1

  @worker_lock :archethic_worker_lock

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    :ets.new(@worker_lock, [:set, :named_table, :public, read_concurrency: true])

    TransactionChain.list_io_transactions([])
    |> Stream.filter(&(&1.data.recipients != []))
    |> Stream.each(fn tx = %Transaction{address: address} ->
      genesis = TransactionChain.get_genesis_address(address)
      load_transaction(tx, genesis, execute_contract?: false)
    end)
    |> Stream.run()

    # Network transactions does not contains trigger or recipient
    TransactionChain.list_all([])
    |> Stream.reject(&Transaction.network_type?(&1.type))
    |> Stream.filter(&(&1.data.recipients != [] or &1.data.code != ""))
    |> Stream.each(fn tx = %Transaction{address: address} ->
      genesis = TransactionChain.get_genesis_address(address)
      load_transaction(tx, genesis, execute_contract?: false)
    end)
    |> Stream.run()

    {:ok, []}
  end

  @doc """
  Load the smart contracts based on transaction involving smart contract code
  """
  @spec load_transaction(
          Transaction.t(),
          genesis_address :: Crypto.prepended_hash(),
          opts :: Keyword.t()
        ) :: :ok
  def load_transaction(tx, genesis_address, opts) do
    execute_contract? = Keyword.fetch!(opts, :execute_contract?)
    download_nodes = Keyword.get(opts, :download_nodes, P2P.authorized_and_available_nodes())
    authorized_nodes = [P2P.get_node_info() | download_nodes] |> P2P.distinct_nodes()
    node_key = Crypto.first_node_public_key()

    handle_contract_chain(tx, genesis_address, node_key, authorized_nodes)
    handle_contract_call(tx, node_key, authorized_nodes, execute_contract?)
  end

  @doc """
  Request to lock a worker so any new call will trigger it.
  To do so, an ets table acts as a mutex using `update_counter` function
  """
  @spec request_worker_lock(genesis_address :: Crypto.prepended_hash()) :: :ok | :already_locked
  def request_worker_lock(genesis_address) do
    # Increment counter by one, if counter > 1 it will returns 2, meaning worker is already locked
    # If increment returns 1, worker was not locked and it is now
    # {2, 1, 1, 2} => position 2, increment by 1, threshold 1, if threshold reach assign 2

    case :ets.update_counter(@worker_lock, genesis_address, {2, 1, 1, 2}, {genesis_address, 0}) do
      1 -> :ok
      2 -> :already_locked
    end
  end

  @doc """
  Unlock a worker as it finished to process calls
  """
  @spec unlock_worker(genesis_address :: Crypto.prepended_hash()) :: integer()
  def unlock_worker(genesis_address),
    do: :ets.update_counter(@worker_lock, genesis_address, {2, -1, 2, 0}, {genesis_address, 0})

  @doc """
  Returns the oldest call for a genesis contract address
  """
  @spec get_next_call(genesis_address :: Crypto.prepended_hash()) ::
          nil | {tx :: Transaction.t(), recipient :: Recipient.t()}
  def get_next_call(genesis_address) do
    calls =
      genesis_address
      |> UTXO.stream_unspent_outputs()
      |> Stream.filter(&(&1.unspent_output.type == :call))
      |> Enum.sort_by(& &1.unspent_output.timestamp, {:asc, DateTime})

    with %VersionedUnspentOutput{unspent_output: %UnspentOutput{from: from}} <- List.first(calls),
         {:ok, tx} <- TransactionChain.get_transaction(from, [], :io) do
      %Transaction{
        data: %TransactionData{recipients: recipients},
        validation_stamp: %ValidationStamp{recipients: resolved_recipients}
      } = tx

      index = Enum.find_index(resolved_recipients, &(&1 == genesis_address))
      recipient = Enum.at(recipients, index)
      {tx, recipient}
    else
      _ -> nil
    end
  end

  @doc """
  Termine a contract execution
  """
  @spec stop_contract(binary()) :: :ok
  def stop_contract(genesis_address) when is_binary(genesis_address) do
    Worker.stop(genesis_address)

    # TransactionChain.clear_pending_transactions(genesis_address)
  end

  defp handle_contract_chain(
         tx = %Transaction{
           address: address,
           type: type,
           data: %TransactionData{code: code}
         },
         genesis_address,
         node_key,
         authorized_nodes
       )
       when code != "" do
    with true <- Election.chain_storage_node?(genesis_address, node_key, authorized_nodes),
         {:ok, contract} <- Contract.from_transaction(tx),
         true <- contract_contains_trigger?(contract) do
      if Worker.exists?(genesis_address),
        do: Worker.set_contract(genesis_address, contract),
        else: Worker.new(genesis_address, contract)

      Logger.info("Smart contract loaded",
        transaction_address: Base.encode16(address),
        transaction_type: type
      )
    else
      _ -> stop_contract(genesis_address)
    end
  end

  defp handle_contract_chain(_, genesis_address, _, _), do: stop_contract(genesis_address)

  defp handle_contract_call(
         %Transaction{
           validation_stamp: %ValidationStamp{
             recipients: resolved_recipients,
             protocol_version: protocol_version
           }
         },
         node_key,
         authorized_nodes,
         execute_contract?
       )
       when length(resolved_recipients) > 0 do
    resolved_recipients
    |> resolve_genesis_address(authorized_nodes, protocol_version)
    |> Enum.each(fn contract_genesis_address ->
      if Election.chain_storage_node?(contract_genesis_address, node_key, authorized_nodes) do
        with true <- execute_contract?,
             {trigger_tx, recipient} <- get_next_call(contract_genesis_address),
             :ok <- request_worker_lock(contract_genesis_address) do
          Worker.execute(contract_genesis_address, trigger_tx, recipient)
        end
      end
    end)
  end

  defp handle_contract_call(_, _, _, _), do: :ok

  defp resolve_genesis_address(recipients, authorized_nodes, protocol_version)
       when protocol_version <= 7 do
    Task.Supervisor.async_stream(
      Archethic.TaskSupervisor,
      recipients,
      fn address ->
        nodes = Election.chain_storage_nodes(address, authorized_nodes)
        TransactionChain.fetch_genesis_address(address, nodes)
      end,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.zip(recipients)
    |> Enum.map(fn
      {{:ok, {:ok, genesis_address}}, recipient} -> {recipient, genesis_address}
      {_, recipient} -> {recipient, recipient}
    end)
  end

  defp resolve_genesis_address(recipients, _, _), do: recipients

  defp contract_contains_trigger?(%Contract{triggers: triggers}) do
    non_empty_triggers =
      Enum.reject(triggers, fn {_, actions} -> actions == {:__block__, [], []} end)

    length(non_empty_triggers) > 0
  end
end
