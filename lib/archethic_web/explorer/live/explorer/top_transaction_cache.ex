defmodule ArchethicWeb.Explorer.ExplorerLive.TopTransactionsCache do
  @table :last_transactions

  @moduledoc false
  use GenServer
  @vsn 1
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_args) do
    :ets.new(@table, [:set, :public, :named_table])
    :ets.insert(@table, {:size, 5, 0})

    {:ok, []}
  end

  @doc """
   Push a Value in Top Transactions Cache
  """
  def push(data) do
    [{_, size, _count}] = :ets.lookup(@table, :size)
    [new_index] = :ets.update_counter(@table, :size, [{3, 1, size, 1}])
    :ets.insert(@table, {{:data, new_index}, data})

    if new_index == 1 do
      :ets.delete(@table, {:data, new_index - size})
    end
  end

  @doc """
    Get all Value from Top Transactions Cache
  """
  def get do
    case :ets.select(@table, [{{{:data, :_}, :"$1"}, [], [:"$1"]}]) do
      [] -> []
      txns -> txns |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    end
  end
end
