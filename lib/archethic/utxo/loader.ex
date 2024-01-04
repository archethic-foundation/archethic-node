defmodule Archethic.UTXO.Loader do
  @moduledoc false

  use GenServer
  @vsn Mix.Project.config()[:version]

  alias Archethic.UTXO.DBLedger
  alias Archethic.UTXO.LoaderSupervisor
  alias Archethic.UTXO.MemoryLedger

  alias Archethic.TransactionChain.Transaction

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  def start_link(arg \\ [], opts \\ []) do
    GenServer.start_link(__MODULE__, arg, opts)
  end

  def add_utxo(utxo = %VersionedUnspentOutput{}, genesis_address) do
    via_tuple = {:via, PartitionSupervisor, {LoaderSupervisor, genesis_address}}
    GenServer.call(via_tuple, {:add_utxo, utxo, genesis_address})
  end

  def consume_inputs(tx = %Transaction{}, genesis_address) do
    via_tuple = {:via, PartitionSupervisor, {LoaderSupervisor, genesis_address}}
    GenServer.call(via_tuple, {:consume_inputs, tx, genesis_address})
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

  def handle_call({:consume_inputs, tx = %Transaction{}, genesis_address}, _, state) do
    # We update the unspent outputs by using the consumed inputs by the transaction
    MemoryLedger.update_chain_unspent_outputs(tx, genesis_address)
    utxos = MemoryLedger.get_unspent_outputs(genesis_address)

    # We compact all the unspent outputs into new ones, cleaning the previous unspent outputs
    DBLedger.flush(genesis_address, utxos)

    {:reply, :ok, state}
  end
end
