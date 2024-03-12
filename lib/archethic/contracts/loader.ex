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
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient

  alias Archethic.UTXO

  require Logger

  use GenServer
  @vsn 1

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    node_key = Crypto.first_node_public_key()
    authorized_nodes = P2P.authorized_and_available_nodes()

    # Network transactions does not contains trigger or recipient
    TransactionChain.list_genesis_addresses()
    |> Stream.filter(&Election.chain_storage_node?(&1, node_key, authorized_nodes))
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
    if execute_contract?, do: handle_contract_call(tx, node_key, authorized_nodes)

    :ok
  end

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
      } = resolve_recipients(tx)

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
           data: %TransactionData{code: code}
         },
         genesis_address,
         node_key,
         authorized_nodes
       )
       when code != "" do
    with true <- Election.chain_storage_node?(genesis_address, node_key, authorized_nodes),
         {:ok, contract} <- Contract.from_transaction(tx),
         true <- Contract.contains_trigger?(contract) do
      if worker_exists?(genesis_address),
        do: Worker.set_contract(genesis_address, contract),
        else: new_contract(genesis_address, contract)

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
end
