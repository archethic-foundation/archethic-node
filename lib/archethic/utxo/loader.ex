defmodule Archethic.UTXO.Loader do
  @moduledoc false

  use GenServer
  @vsn 1

  alias Archethic.UTXO.DBLedger
  alias Archethic.UTXO.LoaderSupervisor
  alias Archethic.UTXO.MemoryLedger

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  def start_link(arg \\ [], opts \\ []) do
    GenServer.start_link(__MODULE__, arg, opts)
  end

  @doc """
  Ingest a new UTXO as input to the chain
  """
  @spec add_utxo(VersionedUnspentOutput.t(), binary()) :: :ok
  def add_utxo(utxo = %VersionedUnspentOutput{}, genesis_address) do
    genesis_address
    |> via_tuple()
    |> GenServer.call({:add_utxo, utxo, genesis_address})
  end

  @doc """
  Ingest the transaction to consumed inputs and allocate the new unspent outputs
  """
  @spec consume_inputs(Transaction.t(), binary()) :: :ok
  def consume_inputs(tx = %Transaction{}, genesis_address) do
    genesis_address
    |> via_tuple()
    |> GenServer.call({:consume_inputs, tx, genesis_address})
  end

  defp via_tuple(genesis_address) do
    {:via, PartitionSupervisor, {LoaderSupervisor, genesis_address}}
  end

  def init(_) do
    {:ok, %{}}
  end

  def handle_call(
        {:add_utxo, utxo = %VersionedUnspentOutput{}, genesis_address},
        _,
        state
      ) do
    DBLedger.append(genesis_address, utxo)
    MemoryLedger.add_chain_utxo(genesis_address, utxo)
    {:reply, :ok, state}
  end

  def handle_call(
        {:consume_inputs,
         %Transaction{
           validation_stamp:
             stamp = %ValidationStamp{
               ledger_operations: %LedgerOperations{consumed_inputs: consumed_inputs}
             }
         }, genesis_address},
        _,
        state
      ) do
    transaction_unspent_outputs = stamp_unspent_outputs(stamp)

    new_unspent_outputs =
      genesis_address
      |> get_unspent_outputs()
      |> Stream.reject(fn %VersionedUnspentOutput{unspent_output: utxo} ->
        utxo in consumed_inputs
      end)
      |> Enum.concat(transaction_unspent_outputs)

    # We compact all the unspent outputs into new ones, cleaning the previous unspent outputs
    DBLedger.flush(genesis_address, new_unspent_outputs)

    # We remove the consumed inputs from the memory ledger
    Enum.each(consumed_inputs, &MemoryLedger.remove_consumed_input(genesis_address, &1))

    # We try to re-insert the new unspent outputs into memory
    Enum.each(transaction_unspent_outputs, &MemoryLedger.add_chain_utxo(genesis_address, &1))

    {:reply, :ok, state}
  end

  def get_unspent_outputs(genesis_address) do
    case MemoryLedger.get_unspent_outputs(genesis_address) do
      [] ->
        DBLedger.stream(genesis_address)

      unspent_outputs ->
        unspent_outputs
    end
  end

  def stamp_unspent_outputs(
        %ValidationStamp{
          protocol_version: protocol_version,
          ledger_operations: %LedgerOperations{
            unspent_outputs: unspent_outputs,
            consumed_inputs: consumed_inputs
          }
        },
        phase2? \\ false
      ) do
    # Filter unspent outputs which have been consumed and updated (required in the AEIP21 Phase 1)
    Enum.filter(unspent_outputs, fn %UnspentOutput{type: type} ->
      phase2? or Enum.any?(consumed_inputs, &(&1.type == type))
    end)
    |> Enum.map(fn utxo = %UnspentOutput{} ->
      %VersionedUnspentOutput{
        unspent_output: utxo,
        protocol_version: protocol_version
      }
    end)
  end
end
