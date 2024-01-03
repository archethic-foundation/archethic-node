defmodule Archethic.Account.GenesisLoader do
  @moduledoc false

  use GenServer
  @vsn Mix.Project.config()[:version]

  alias Archethic.Account.GenesisPendingLog
  alias Archethic.Account.GenesisLoaderSupervisor
  alias Archethic.Account.GenesisState
  alias Archethic.Account.MemTables.GenesisInputLedger

  alias Archethic.Crypto
  alias Archethic.DB
  alias Archethic.Election

  alias Archethic.P2P

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.Utils

  def start_link(arg \\ [], opts \\ []) do
    GenServer.start_link(__MODULE__, arg, opts)
  end

  def setup_folders!() do
    File.mkdir_p!(GenesisPendingLog.base_path())
    File.mkdir_p!(GenesisState.base_path())
  end

  def load_transaction(tx = %Transaction{}, io_transaction?) do
    authorized_nodes = P2P.authorized_and_available_nodes()

    # Ingest all the movements to fill up the UTXO list
    ingest_genesis_input(tx, authorized_nodes)

    consume_genesis_inputs(tx, io_transaction?, authorized_nodes)
  end

  defp ingest_genesis_input(
         %Transaction{
           address: address,
           validation_stamp: %ValidationStamp{
             protocol_version: protocol_version,
             timestamp: timestamp,
             ledger_operations: %LedgerOperations{transaction_movements: transaction_movements}
           }
         },
         authorized_nodes
       ) do
    Enum.each(
      transaction_movements,
      fn %TransactionMovement{to: to, amount: amount, type: type} ->
        genesis_address =
          case DB.find_genesis_address(to) do
            {:ok, address} ->
              address

            _ ->
              # Support when the resolved address is the genesis address
              to
          end

        tx_input = %VersionedTransactionInput{
          input: %TransactionInput{
            from: address,
            amount: amount,
            timestamp: timestamp,
            type: type
          },
          protocol_version: protocol_version
        }

        if genesis_node?(genesis_address, authorized_nodes) do
          via_tuple = {:via, PartitionSupervisor, {GenesisLoaderSupervisor, genesis_address}}
          GenServer.call(via_tuple, {:add_input, tx_input, genesis_address})
        end
      end
    )
  end

  defp consume_genesis_inputs(
         tx = %Transaction{
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{consumed_inputs: consumed_inputs}
           }
         },
         io_transaction?,
         authorized_nodes
       ) do
    case find_genesis_address(tx) do
      {:ok, genesis_address} ->
        # We need to determine whether the node is responsible of the chain genesis pool as the transaction have been received as an I/O transaction.
        chain_transaction? =
          (not io_transaction? or TransactionChain.get_size(genesis_address) > 0) and
            genesis_node?(genesis_address, authorized_nodes)

        # In case, this transaction is one of the genesis chains, we have to consume inputs
        if chain_transaction? and length(consumed_inputs) > 0 do
          via_tuple = {:via, PartitionSupervisor, {GenesisLoaderSupervisor, genesis_address}}
          GenServer.call(via_tuple, {:consumed_inputs, tx, genesis_address})
        end

      _ ->
        # ignore if genesis's address is not found
        :ok
    end
  end

  def init(_) do
    {:ok, %{}}
  end

  def handle_call(
        {:add_input, tx_input = %VersionedTransactionInput{}, genesis_address},
        _,
        state
      ) do
    GenesisPendingLog.append(genesis_address, tx_input)
    GenesisInputLedger.add_chain_input(genesis_address, tx_input)
    {:reply, :ok, state}
  end

  def handle_call({:consumed_inputs, tx = %Transaction{}, genesis_address}, _, state) do
    # We update the UTXOs by using the consumed inputs by the transaction
    GenesisInputLedger.update_chain_inputs(tx, genesis_address)
    utxos = GenesisInputLedger.get_unspent_inputs(genesis_address)

    # We flush the serialized state of the genesis UTXOs
    GenesisState.persist(genesis_address, utxos)

    # Once the state have been serialized, we can clean the pending log of inputs
    GenesisPendingLog.clear(genesis_address)

    {:reply, :ok, state}
  end

  defp find_genesis_address(tx = %Transaction{address: address}) do
    case DB.find_genesis_address(address) do
      {:ok, genesis_address} ->
        # This happens when the last transaction is ingested in the system (i.e last's tx chain)
        {:ok, genesis_address}

      {:error, :not_found} ->
        # This might happens when the transaction haven't been yet synchronized but the previous transaction is already in the system (i.e genesis's chain)
        DB.find_genesis_address(Transaction.previous_address(tx))
    end
  end

  defp genesis_node?(genesis_address, nodes) do
    genesis_nodes = Election.chain_storage_nodes(genesis_address, nodes)
    Utils.key_in_node_list?(genesis_nodes, Crypto.first_node_public_key())
  end
end
