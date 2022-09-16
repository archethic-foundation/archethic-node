defmodule ArchethicWeb.ExplorerLive.TopTransactionsCache do
  alias Archethic.TransactionChain.TransactionSummary

  @table :last_ten_transactions

  @moduledoc false
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_args) do
    :ets.new(@table, [:set, :public, :named_table])

    {:ok, []}
  end

  @doc """
  Retrieve a value from cache
  """
  def get(address) do
    GenServer.call(__MODULE__, {:get, address})
  end

  def get_all() do
    GenServer.call(__MODULE__, :get_all)
  end

  def handle_call(:get_all, _, state) do
    result = :ets.match(@table, :"$1")
    {:reply, result, state}
  end

  def handle_call({:get, address}, _, state) do
    Logger.debug("Fetching from cache")

    result =
      case :ets.lookup(@table, address) do
        [{^address, value}] ->
          {value}

        _ ->
          nil
      end

    {:reply, result, state}
  end

  @doc """
  Runs a piece of code if not already cached
  """
  def resolve(resolver) when is_function(resolver, 0) do
    case get_all() do
      [] ->
        with result <- resolver.() do
          Logger.debug("Caching results for last 10 Transactions")

          Enum.each(result, fn %TransactionSummary{address: address} = txn ->
            :ets.insert(@table, {address, txn})
            txn
          end)

          {:ok, result}
        end

      txns ->
        Logger.debug("Found in cache for last 10 Transactions")

        txns =
          Enum.map(txns, fn [{_, txn}] -> txn end)
          |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})

        {:ok, txns}
    end
  end

  @doc """
  Update the Local Cache Transaction and pop last txn
  """
  def resolve_put(%TransactionSummary{address: address} = txn, resolver)
      when is_function(resolver, 0) do
    case get_all() do
      [] ->
        with result <- resolver.() do
          Logger.debug("Caching results for last 10 Transactions")

          Enum.each(result, fn %TransactionSummary{address: address} = txn ->
            :ets.insert(@table, {address, txn})
            txn
          end)

          {:ok, result}
        end

      txns ->
        Logger.debug("Updating Transaction...")

        txns =
          txns
          |> Enum.map(fn [{_, txn}] -> txn end)
          |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
          |> List.insert_at(0, txn)

        %TransactionSummary{address: address_last} = txns |> List.last()
        :ets.delete(@table, address_last)
        :ets.insert(@table, {address, txn})

        {:ok, txns}
    end
  end
end
