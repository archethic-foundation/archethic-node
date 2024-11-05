defmodule Archethic.Contracts.Loader do
  @moduledoc false

  alias Archethic.ContractRegistry
  alias Archethic.ContractSupervisor

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Worker

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient

  alias Archethic.UTXO

  require Logger

  use GenServer
  @vsn 1

  @invalid_call_table :archethic_invalid_call

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    :ets.new(@invalid_call_table, [:bag, :named_table, :public, read_concurrency: true])

    node_key = Crypto.first_node_public_key()
    authorized_nodes = P2P.authorized_and_available_nodes()

    # Network transactions does not contains trigger or recipient
    TransactionChain.list_genesis_addresses()
    |> Stream.filter(&Election.chain_storage_node?(&1, node_key, authorized_nodes))
    |> Stream.chunk_every(100)
    |> Task.async_stream(
      fn genesis_addresses ->
        genesis_addresses
        |> Stream.map(fn genesis -> {genesis, TransactionChain.get_last_transaction(genesis)} end)
        |> Stream.reject(fn
          {_, {:ok, %Transaction{type: type, data: %TransactionData{code: code}}}} ->
            Transaction.network_type?(type) or code == ""

          {_, {:error, _}} ->
            true
        end)
        |> Stream.each(fn {genesis, {:ok, tx}} ->
          load_transaction(tx, genesis, execute_contract?: false)
        end)
        |> Stream.run()
      end,
      timeout: :infinity,
      max_concurrency: 16
    )
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

    handle_contract_chain(tx, genesis_address, node_key, authorized_nodes, execute_contract?)
    if execute_contract?, do: handle_contract_call(tx, node_key, authorized_nodes)

    :ok
  end

  @doc """
  Set a call as invalid since it failed to create a valid transaction
  """
  @spec invalidate_call(
          contract_genesis :: Crypto.prepended_hash(),
          contract_address :: Crypto.prepended_hash(),
          call_address :: Crypto.prepended_hash()
        ) :: any()
  def invalidate_call(contract_genesis, contract_address, call_address) do
    previous_invalid_call =
      @invalid_call_table
      |> :ets.lookup(contract_genesis)
      |> Enum.find(fn {_, _, address} -> address == call_address end)

    if previous_invalid_call != nil,
      do: :ets.delete_object(@invalid_call_table, previous_invalid_call)

    :ets.insert(@invalid_call_table, {contract_genesis, contract_address, call_address})
  end

  @doc """
  Returns the oldest call for a genesis contract address
  """
  @spec get_next_call(
          genesis_address :: Crypto.prepended_hash(),
          contract_address :: Crypto.prepended_hash()
        ) :: nil | {tx :: Transaction.t(), recipient :: Recipient.t()}
  def get_next_call(genesis_address, contract_address) do
    calls =
      genesis_address
      |> UTXO.stream_unspent_outputs()
      |> Enum.filter(&(&1.unspent_output.type == :call))
      |> handle_invalid_calls(genesis_address, contract_address)
      |> Enum.sort({:asc, VersionedUnspentOutput})

    with %VersionedUnspentOutput{unspent_output: %UnspentOutput{from: from}} <- List.first(calls),
         {:ok, tx} <- TransactionChain.get_transaction(from, [], :io) do
      %Transaction{
        data: %TransactionData{recipients: recipients},
        validation_stamp: %ValidationStamp{recipients: resolved_recipients}
      } = resolve_recipients(tx)

      index = Enum.find_index(resolved_recipients, &(&1 == genesis_address))
      recipient = Enum.at(recipients, index)
      {tx, recipient}
    else
      _ -> nil
    end
  end

  @doc """
  Function used during hot reload !
  It request contracts to reparse their contract code since some modification
  in contract interpreter could update the parsed code
  """
  @spec reparse_workers_contract() :: :ok
  def reparse_workers_contract() do
    ContractSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn
      {_, pid, _, _} when is_pid(pid) -> GenStateMachine.cast(pid, :reparse_contract)
      _ -> :ignore
    end)
  end

  defp handle_invalid_calls([], _, _), do: []

  defp handle_invalid_calls(calls, genesis_address, current_contract_address) do
    invalid_calls = :ets.lookup(@invalid_call_table, genesis_address)

    case reject_invalid_calls(calls, invalid_calls) do
      [] -> reject_current_invalid_calls(calls, invalid_calls, current_contract_address)
      calls -> calls
    end
  end

  defp reject_invalid_calls(calls, []), do: calls

  defp reject_invalid_calls(calls, invalid_calls) do
    Enum.reject(
      calls,
      &Enum.find_value(invalid_calls, false, fn {_, _, invalid_call_address} ->
        &1.unspent_output.from == invalid_call_address
      end)
    )
  end

  defp reject_current_invalid_calls(calls, invalid_calls, current_contract_address) do
    Enum.reject(
      calls,
      &Enum.find_value(invalid_calls, false, fn {_, contract_address, invalid_call_address} ->
        &1.unspent_output.from == invalid_call_address and
          contract_address == current_contract_address
      end)
    )
  end

  @doc """
  Termine a contract execution
  """
  @spec stop_contract(binary()) :: :ok
  def stop_contract(genesis_address) when is_binary(genesis_address) do
    :ets.delete(@invalid_call_table, genesis_address)

    case GenServer.whereis({:via, Registry, {ContractRegistry, genesis_address}}) do
      nil ->
        :ok

      pid ->
        Logger.info("Stop smart contract at #{Base.encode16(genesis_address)}")
        DynamicSupervisor.terminate_child(ContractSupervisor, pid)
    end

    # TransactionChain.clear_pending_transactions(genesis_address)
  end

  defp resolve_recipients(
         tx = %Transaction{
           validation_stamp: %ValidationStamp{protocol_version: protocol_version}
         }
       )
       when protocol_version <= 7 do
    update_in(tx, [Access.key!(:validation_stamp), Access.key!(:recipients)], fn recipients ->
      Enum.map(recipients, &TransactionChain.get_genesis_address/1)
    end)
  end

  defp resolve_recipients(tx), do: tx

  defp worker_exists?(genesis_address),
    do: Registry.lookup(ContractRegistry, genesis_address) != []

  defp new_contract(genesis_address, contract) do
    DynamicSupervisor.start_child(
      ContractSupervisor,
      {Worker, contract: contract, genesis_address: genesis_address}
    )
  end

  defp handle_contract_chain(
         tx = %Transaction{
           address: address,
           type: type,
           data: %TransactionData{code: code},
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{consumed_inputs: consumed_inputs}
           }
         },
         genesis_address,
         node_key,
         authorized_nodes,
         execute_contract?
       )
       when code != "" do
    remove_invalid_input(genesis_address, consumed_inputs)

    with true <- Election.chain_storage_node?(genesis_address, node_key, authorized_nodes),
         {:ok, contract} <- Contract.from_transaction(tx),
         true <- Contract.contains_trigger?(contract) do
      if worker_exists?(genesis_address),
        do: Worker.set_contract(genesis_address, contract, execute_contract?),
        else: new_contract(genesis_address, contract)

      Logger.info("Smart contract loaded",
        transaction_address: Base.encode16(address),
        transaction_type: type
      )
    else
      _ -> stop_contract(genesis_address)
    end
  end

  defp handle_contract_chain(_, genesis_address, _, _, _), do: stop_contract(genesis_address)

  defp remove_invalid_input(genesis_address, consumed_inputs) do
    consumed_calls_address =
      consumed_inputs
      |> Enum.filter(&(&1.unspent_output.type == :call))
      |> Enum.map(& &1.unspent_output.from)

    @invalid_call_table
    |> :ets.lookup(genesis_address)
    |> Enum.each(fn obj = {_, _, call_address} ->
      if Enum.member?(consumed_calls_address, call_address) do
        :ets.delete_object(@invalid_call_table, obj)
      end
    end)
  end

  defp handle_contract_call(
         %Transaction{
           validation_stamp: %ValidationStamp{
             recipients: resolved_recipients,
             protocol_version: protocol_version
           }
         },
         node_key,
         authorized_nodes
       )
       when length(resolved_recipients) > 0 do
    resolved_recipients
    |> resolve_genesis_address(authorized_nodes, protocol_version)
    |> Enum.each(fn contract_genesis_address ->
      if Election.chain_storage_node?(contract_genesis_address, node_key, authorized_nodes) do
        Worker.process_next_trigger(contract_genesis_address)
      end
    end)
  end

  defp handle_contract_call(_, _, _), do: :ok

  defp resolve_genesis_address(recipients, authorized_nodes, protocol_version)
       when protocol_version <= 7 do
    Task.Supervisor.async_stream(
      Archethic.task_supervisors(),
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
end
