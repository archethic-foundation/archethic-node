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

  def handle_call({:consume_inputs, tx = %Transaction{}, genesis_address}, _, state) do
    # We update the unspent outputs by using the consumed inputs by the transaction
    MemoryLedger.update_chain_unspent_outputs(tx, genesis_address)
    utxos = MemoryLedger.get_unspent_outputs(genesis_address)

    # We compact all the unspent outputs into new ones, cleaning the previous unspent outputs
    DBLedger.flush(genesis_address, utxos)

    {:reply, :ok, state}
  end
end
