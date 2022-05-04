defmodule Archethic.BeaconChain.Subset.SummaryCache do
  @moduledoc """
  Handle the caching of the beacon slots defined for the summary
  """

  alias Archethic.BeaconChain.Slot

  use GenServer

  @table_name :archethic_summary_cache

  def start_link(arg \\ []) do
    GenServer.start_link(__MODULE__, arg)
  end

  def init(_) do
    :ets.new(:archethic_summary_cache, [
      :bag,
      :named_table,
      :public,
      read_concurrency: true
    ])

    {:ok, %{}}
  end

  @doc """
  Extract all the entries in the cache
  """
  @spec pop_slots(subset :: binary()) :: list(Slot.t())
  def pop_slots(subset) do
    :ets.take(@table_name, subset)
    |> Enum.map(fn {_, slot} ->
      slot
    end)
  end

  @doc """
  Add new beacon slots to the summary's cache
  """
  @spec add_slot(subset :: binary(), Slot.t()) :: :ok
  def add_slot(subset, slot = %Slot{}) do
    true = :ets.insert(@table_name, {subset, slot})
    :ok
  end
end
