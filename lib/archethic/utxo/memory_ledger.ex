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

        Logger.debug(
          "UTXO #{Base.encode16(from)}@#{inspect(type)} added for genesis #{Base.encode16(genesis_address)}"
        )

        :ok
    end
  end

  @doc """
  Remove of the consumed input from the memory ledger for the given genesis
  """
  @spec remove_consumed_input(binary(), UnspentOutput.t()) :: :ok
  def remove_consumed_input(genesis_address, utxo = %UnspentOutput{from: from}) do
    Logger.debug("Consuming #{Base.encode16(from)} - for #{Base.encode16(genesis_address)}")

    match = [
      {{genesis_address, %{__struct__: VersionedUnspentOutput, unspent_output: utxo}}, [],
       [:"$_"]}
    ]

    Enum.each(:ets.select(@table_name, match), fn elem = {_, utxo} ->
      size = :erlang.external_size(utxo)
      :ets.delete_object(@table_name, elem)
      :ets.update_counter(@table_stats_name, genesis_address, {2, -size})
    end)

    :ok
  end

  @doc """
  Returns the list of all the inputs which have not been consumed for the given chain's address
  """
  @spec stream_unspent_outputs(binary()) :: Enumerable.t() | list(VersionedUnspentOutput.t())
  def stream_unspent_outputs(genesis_address) do
    match_pattern = [{{:"$1", :"$2"}, [{:==, :"$1", genesis_address}], [:"$2"]}]

    Stream.resource(
      fn ->
        # Fix the table to avoid "invalid continuation" error
        # source: https://www.erlang.org/doc/man/ets#safe_fixtable-2
        :ets.safe_fixtable(@table_name, true)
        :ets.select(@table_name, match_pattern, 1)
      end,
      &do_stream_genesis_utxo/1,
      fn _ ->
        :ets.safe_fixtable(@table_name, false)
        :ok
      end
    )
  end

  defp do_stream_genesis_utxo(:"$end_of_table") do
    {:halt, :"$end_of_table"}
  end

  defp do_stream_genesis_utxo({utxo, continuation}) do
    {utxo, :ets.select(continuation)}
  end

  @spec get_genesis_stats(binary()) :: %{size: non_neg_integer()}
  def get_genesis_stats(genesis_address) do
    case :ets.lookup(@table_stats_name, genesis_address) do
      [] ->
        %{size: 0}

      [{_, size}] ->
        %{size: size}
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
