defmodule Archethic.UTXO do
  @moduledoc false
  alias Archethic.DB

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.Utils

  alias Archethic.UTXO.DBLedger
  alias Archethic.UTXO.Loader
  alias Archethic.UTXO.MemoryLedger

  require Logger

  @type load_opts :: [io_transaction?: boolean()]

  @spec load_transaction(Transcation.t(), load_opts()) :: :ok
  def load_transaction(tx = %Transaction{}, opts \\ []) do
    io_transaction? = Keyword.get(opts, :io_transaction?, false)
    authorized_nodes = P2P.authorized_and_available_nodes()

    # Ingest all the movements to fill up the UTXO list
    ingest_utxo(tx, authorized_nodes)

    consume_utxo(tx, io_transaction?, authorized_nodes)

    Logger.info("Loaded into in memory UTXO tables",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )
  end

  defp ingest_utxo(
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

        utxo = %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: address,
            amount: amount,
            timestamp: timestamp,
            type: type
          },
          protocol_version: protocol_version
        }

        if genesis_node?(genesis_address, authorized_nodes) do
          Loader.add_utxo(utxo, genesis_address)
        end
      end
    )
  end

  defp consume_utxo(
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
          Loader.consume_inputs(tx, genesis_address)
        end

      _ ->
        # ignore if genesis's address is not found
        :ok
    end
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

  @doc """
  Returns the list of all the inputs which have not been consumed for the given chain's address
  """
  @spec get_unspent_outputs(binary()) :: list(VersionedUnspentOutput.t())
  def get_unspent_outputs(address) do
    case MemoryLedger.get_unspent_outputs(address) do
      [] ->
        DBLedger.stream(address)

      unspent_outputs ->
        unspent_outputs
    end
  end
end
