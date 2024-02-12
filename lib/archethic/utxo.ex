defmodule Archethic.UTXO do
  @moduledoc false
  alias Archethic.DB

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P

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

  @spec load_transaction(tx :: Transaction.t(), genesis_address :: Crypto.prepended_hash()) :: :ok
  def load_transaction(
        tx = %Transaction{validation_stamp: %ValidationStamp{protocol_version: protocol_version}},
        genesis_address
      ) do
    authorized_nodes = P2P.authorized_and_available_nodes()
    node_public_key = Crypto.first_node_public_key()

    # Ingest all the movements and recipients to fill up the UTXO list
    ingest_movements(tx, authorized_nodes)
    ingest_recipients(tx, authorized_nodes)

    # Consume the transaction to update the unspent outputs from the consumed inputs
    if Election.chain_storage_node?(genesis_address, node_public_key, authorized_nodes),
      do: Loader.consume_inputs(tx, genesis_address)

    Logger.info("Loaded into in memory UTXO tables",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )
  end

  defp ingest_movements(
         %Transaction{
           address: address,
           type: tx_type,
           validation_stamp: %ValidationStamp{
             protocol_version: protocol_version,
             timestamp: timestamp,
             ledger_operations: %LedgerOperations{transaction_movements: transaction_movements}
           }
         },
         authorized_nodes
       ) do
    transaction_movements
    |> consolidate_movements(protocol_version, tx_type)
    |> Enum.each(fn %TransactionMovement{to: to, amount: amount, type: type} ->
      genesis_address = DB.get_genesis_address(to)

      if genesis_node?(genesis_address, authorized_nodes) do
        utxo = %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: address,
            amount: amount,
            timestamp: timestamp,
            type: type
          },
          protocol_version: protocol_version
        }

        Loader.add_utxo(utxo, genesis_address)
      end
    end)
  end

  defp ingest_recipients(
         %Transaction{
           address: address,
           validation_stamp: %ValidationStamp{
             recipients: recipients,
             timestamp: timestamp,
             protocol_version: protocol_version
           }
         },
         authorized_nodes
       ) do
    recipients
    |> Enum.each(fn recipient ->
      genesis_address = DB.get_genesis_address(recipient)

      if genesis_node?(genesis_address, authorized_nodes) do
        utxo = %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: address,
            type: :call,
            timestamp: timestamp
          },
          protocol_version: protocol_version
        }

        Loader.add_utxo(utxo, genesis_address)
      end
    end)
  end

  defp consolidate_movements(transaction_movements, protocol_version, tx_type)
       when protocol_version < 5 do
    transaction_movements
    |> Enum.map(fn movement -> TransactionMovement.maybe_convert_reward(movement, tx_type) end)
    |> TransactionMovement.aggregate()
  end

  defp consolidate_movements(transaction_movements, _protocol_version, _tx_type),
    do: transaction_movements

  defp genesis_node?(genesis_address, nodes) do
    genesis_nodes = Election.chain_storage_nodes(genesis_address, nodes)
    Utils.key_in_node_list?(genesis_nodes, Crypto.first_node_public_key())
  end

  @doc """
  Returns the list of all the inputs which have not been consumed for the given chain's address
  """
  @spec stream_unspent_outputs(binary()) :: list(VersionedUnspentOutput.t())
  def stream_unspent_outputs(address) do
    mem_stream = MemoryLedger.stream_unspent_outputs(address)

    if Enum.empty?(mem_stream) do
      DBLedger.stream(address)
    else
      mem_stream
    end
  end
end
