defmodule Archethic.UTXO.MemoryLedger do
  @moduledoc """
  Represents a memory table for all the inputs associated to a chain
  to give the latest view of unspent outputs based on the consumed inputs
  """

  use GenServer
  @vsn Mix.Project.config()[:version]

  @table_name :archethic_utxo_ledger
  @table_stats_name :archethic_utxo_ledger_stats

  @threshold Application.compile_env(:archethic, __MODULE__) |> Keyword.fetch!(:size_threshold)

  require Logger

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.UTXO.DBLedger

  @spec start_link(arg :: list()) :: GenServer.on_start()
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_args) do
    Logger.info("Initialize InMemory UTXO Ledger...")

    :ets.new(@table_name, [:bag, :named_table, :public, read_concurrency: true])
    :ets.new(@table_stats_name, [:set, :named_table, :public, read_concurrency: true])
    load()

    {:ok, %{table_name: @table_name}}
  end

  defp load() do
    DBLedger.list_genesis_addresses()
    |> Task.async_stream(fn genesis_address ->
      genesis_address
      |> DBLedger.stream()
      |> Enum.each(&add_chain_utxo(genesis_address, &1))
    end)
    |> Stream.run()
  end

  @doc """
  Add new utxo in the genesis ledger
  """
  @spec add_chain_utxo(
          genesis_address :: binary(),
          unspent_output :: VersionedUnspentOutput.t()
        ) :: :ok
  def add_chain_utxo(
        genesis_address,
        utxo = %VersionedUnspentOutput{unspent_output: %UnspentOutput{from: from, type: type}}
      )
      when is_binary(genesis_address) do
    size = :erlang.external_size(utxo)
    :ets.insert(@table_name, {genesis_address, utxo})

    case :ets.lookup(@table_stats_name, genesis_address) do
      [{_, previous_size}] when previous_size + size >= @threshold ->
        :ets.delete(@table_stats_name, genesis_address)
        :ets.delete(@table_name, genesis_address)
        Logger.debug("UTXO ledger for #{Base.encode16(genesis_address)} evicted from memory")

      _ ->
        :ets.update_counter(@table_stats_name, genesis_address, {2, size}, {genesis_address, 0})

        Logger.debug(
          "UTXO #{Base.encode16(from)}@#{inspect(type)} added for genesis #{inspect(genesis_address)}"
        )

        :ok
    end
  end

  @doc """
  Update the chain unspent outputs after reduce of the consumed transaction inputs
  """
  @spec update_chain_unspent_outputs(Transaction.t(), genesis_address :: binary()) :: :ok
  def update_chain_unspent_outputs(
        %Transaction{
          validation_stamp: %ValidationStamp{
            ledger_operations: %LedgerOperations{
              consumed_inputs: consumed_inputs,
              unspent_outputs: unspent_outputs
            },
            protocol_version: protocol_version
          }
        },
        genesis_address,
        phase2? \\ false
      )
      when is_binary(genesis_address) do
    # Filter unspent outputs which have been consumed and updated (required in the AEIP21 Phase 1)
    updated_unspent_outputs =
      Enum.filter(unspent_outputs, fn %UnspentOutput{type: type} ->
        phase2? or Enum.any?(consumed_inputs, &(&1.type == type))
      end)
      |> Enum.map(fn utxo = %UnspentOutput{} ->
        %VersionedUnspentOutput{
          unspent_output: utxo,
          protocol_version: protocol_version
        }
      end)

    # Remove the consumed inputs
    Enum.each(
      consumed_inputs,
      fn %UnspentOutput{
           from: from,
           type: type,
           amount: amount,
           timestamp: timestamp
         } ->
        Logger.debug("Consuming #{Base.encode16(from)} - for #{inspect(genesis_address)}")

        pattern =
          {genesis_address,
           %{
             __struct__: VersionedUnspentOutput,
             unspent_output: %{
               __struct__: UnspentOutput,
               amount: amount,
               from: from,
               timestamp: timestamp,
               type: type
             }
           }}

        :ets.match_delete(@table_name, pattern)
      end
    )

    # Reset size stats for this genesis's address
    :ets.delete(@table_stats_name, genesis_address)
    Enum.each(updated_unspent_outputs, &add_chain_utxo(genesis_address, &1))
  end

  @doc """
  Returns the list of all the inputs which have not been consumed for the given chain's address
  """
  @spec get_unspent_outputs(binary()) :: list(VersionedTransactionInput.t())
  def get_unspent_outputs(genesis_address) do
    @table_name
    |> :ets.lookup(genesis_address)
    |> Enum.map(&elem(&1, 1))
  end
end
