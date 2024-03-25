defmodule Archethic.UTXO.MemoryLedger do
  @moduledoc """
  Represents a memory table for all the inputs associated to a chain
  to give the latest view of unspent outputs based on the consumed inputs
  """

  use GenServer
  @vsn 1

  @table_name :archethic_utxo_ledger
  @table_stats_name :archethic_utxo_ledger_stats

  @threshold Application.compile_env(:archethic, __MODULE__) |> Keyword.fetch!(:size_threshold)

  require Logger

  alias Archethic.Crypto

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
          genesis_address :: Crypto.prepended_hash(),
          unspent_output :: VersionedUnspentOutput.t()
        ) :: :ok
  def add_chain_utxo(
        genesis_address,
        utxo = %VersionedUnspentOutput{unspent_output: %UnspentOutput{from: from, type: type}}
      )
      when is_binary(genesis_address) do
    size = :erlang.external_size(utxo)

    case :ets.lookup(@table_stats_name, genesis_address) do
      [{_, previous_size}] when previous_size >= @threshold ->
        :ets.insert(@table_stats_name, {genesis_address, previous_size + size})

      [{_, previous_size}] when previous_size + size >= @threshold ->
        :ets.insert(@table_stats_name, {genesis_address, previous_size + size})
        :ets.delete(@table_name, genesis_address)
        Logger.debug("UTXO ledger for #{Base.encode16(genesis_address)} evicted from memory")

      _ ->
        :ets.insert(@table_name, {genesis_address, utxo})
        :ets.update_counter(@table_stats_name, genesis_address, {2, size}, {genesis_address, 0})

        if from != nil do
          Logger.debug(
            "UTXO #{Base.encode16(from)}@#{UnspentOutput.type_to_str(type)} added for genesis #{Base.encode16(genesis_address)}"
          )
        else
          Logger.debug(
            "UTXO type #{UnspentOutput.type_to_str(type)} added for genesis #{Base.encode16(genesis_address)}"
          )
        end

        :ok
    end
  end

  @doc """
  Remove of the consumed input from the memory ledger for the given genesis
  """
  @spec remove_consumed_inputs(
          genesis_address :: Crypto.prepended_hash(),
          utxos :: list(VersionedUnspentOutput.t())
        ) :: :ok
  def remove_consumed_inputs(genesis_address, utxos) do
    :ets.lookup(@table_name, genesis_address)
    |> Enum.filter(fn {_, utxo} -> Enum.member?(utxos, utxo) end)
    |> Enum.each(fn elem = {_, utxo} ->
      size = :erlang.external_size(utxo)
      :ets.delete_object(@table_name, elem)
      :ets.update_counter(@table_stats_name, genesis_address, {2, -size})

      %VersionedUnspentOutput{unspent_output: %UnspentOutput{from: from, type: type}} = utxo

      if from != nil do
        Logger.debug("Consuming #{Base.encode16(from)} - for #{Base.encode16(genesis_address)}")
      else
        Logger.debug(
          "Consuming #{UnspentOutput.type_to_str(type)} - for #{Base.encode16(genesis_address)}"
        )
      end
    end)
  end

  @doc """
  Returns true if the threshold limit is reached for a genesis address
  """
  @spec threshold_reached?(genesis_address :: Crypto.prepended_hash()) :: boolean()
  def threshold_reached?(genesis_address) do
    %{size: size} = get_genesis_stats(genesis_address)
    size >= @threshold
  end

  @doc """
  Returns the list of all the inputs which have not been consumed for the given chain's address
  """
  @spec get_unspent_outputs(binary()) :: list(VersionedUnspentOutput.t())
  def get_unspent_outputs(genesis_address) do
    @table_name
    |> :ets.lookup(genesis_address)
    |> Enum.map(fn {_, utxo} -> utxo end)
  end

  @spec get_genesis_stats(binary()) :: %{size: non_neg_integer()}
  def get_genesis_stats(genesis_address) do
    case :ets.lookup(@table_stats_name, genesis_address) do
      [] -> %{size: 0}
      [{_, size}] -> %{size: size}
    end
  end

  @doc """
  Remove UTXO entries from a given genesis
  """
  @spec clear_genesis(binary()) :: :ok
  def clear_genesis(genesis_address) do
    :ets.delete(@table_name, genesis_address)
    :ets.delete(@table_stats_name, genesis_address)
    :ok
  end
end
