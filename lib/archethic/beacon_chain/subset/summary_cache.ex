defmodule Archethic.BeaconChain.Subset.SummaryCache do
  @moduledoc """
  Handle the caching of the beacon slots defined for the summary
  """

  alias Archethic.BeaconChain.Slot

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  alias Archethic.BeaconChain.SummaryTimer

  use GenServer

  @table_name :archethic_summary_cache

  def start_link(arg \\ []) do
    GenServer.start_link(__MODULE__, arg)
  end

  def init(_) do
    :ets.new(@table_name, [
      :bag,
      :named_table,
      :public,
      read_concurrency: true
    ])

    :ok = recover_slots()

    {:ok, %{}}
  end

  @doc """
  Extract all the entries in the cache
  """
  @spec pop_slots(subset :: binary()) :: list(Slot.t())
  def pop_slots(subset) do
    recover_path() |> File.rm()

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
    backup_slot(subset, slot)
  end

  defp recover_path(), do: Utils.mut_dir("slot_backup")

  defp backup_slot(subset, slot) do
    content = serialize(subset, slot)

    recover_path()
    |> File.write!(content, [:append, :binary])
  end

  defp recover_slots() do
    if File.exists?(recover_path()) do
      next_summary_time = DateTime.utc_now() |> SummaryTimer.next_summary() |> DateTime.to_unix()

      content = File.read!(recover_path())

      deserialize(content, [])
      |> Enum.each(fn {summary_time, subset, slot} ->
        if summary_time == next_summary_time, do: true = :ets.insert(@table_name, {subset, slot})
      end)
    else
      :ok
    end
  end

  defp serialize(subset, slot = %Slot{slot_time: slot_time}) do
    summary_time = SummaryTimer.next_summary(slot_time) |> DateTime.to_unix()
    slot_bin = Slot.serialize(slot) |> Utils.wrap_binary()
    slot_size = byte_size(slot_bin) |> VarInt.from_value()

    <<summary_time::32, subset::binary, slot_size::binary, slot_bin::binary>>
  end

  defp deserialize(<<>>, acc), do: acc

  defp deserialize(rest, acc) do
    <<summary_time::32, subset::8, rest::binary>> = rest
    {slot_size, rest} = VarInt.get_value(rest)
    <<slot_bin::binary-size(slot_size), rest::binary>> = rest
    {slot, _} = Slot.deserialize(slot_bin)

    deserialize(rest, [{summary_time, <<subset>>, slot} | acc])
  end
end
