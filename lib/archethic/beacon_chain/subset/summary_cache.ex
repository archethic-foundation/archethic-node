defmodule Archethic.BeaconChain.Subset.SummaryCache do
  @moduledoc """
  Handle the caching of the beacon slots defined for the summary
  """

  alias Archethic.BeaconChain.Slot
  alias Archethic.Crypto

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  alias Archethic.BeaconChain.SummaryTimer

  use GenServer
  @vsn Mix.Project.config()[:version]

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
  Stream all the entries for a subset
  """
  @spec stream_current_slots(subset :: binary()) ::
          Enumerable.t() | list({Slot.t(), Crypto.key()})
  def stream_current_slots(subset) do
    # generate match pattern
    # :ets.fun2ms(fn {key, value} when key == subset -> value end)
    match_pattern = [{{:"$1", :"$2"}, [{:==, :"$1", subset}], [:"$2"]}]

    Stream.resource(
      fn -> :ets.select(@table_name, match_pattern, 1) end,
      &do_stream_current_slots/1,
      fn _ -> :ok end
    )
  end

  defp do_stream_current_slots(:"$end_of_table") do
    {:halt, :"$end_of_table"}
  end

  defp do_stream_current_slots({slot, continuation}) do
    {slot, :ets.select(continuation)}
  end

  @doc """
  Extract all the entries in the cache
  """
  @spec pop_slots(subset :: binary()) :: list({Slot.t(), Crypto.key()})
  def pop_slots(subset) do
    recover_path() |> File.rm()

    :ets.take(@table_name, subset)
    |> Enum.map(fn
      {_, {slot = %Slot{}, _}} ->
        slot

      {_, slot = %Slot{}} ->
        slot
    end)
  end

  @doc """
  Add new beacon slots to the summary's cache
  """
  @spec add_slot(subset :: binary(), Slot.t(), Crypto.key()) :: :ok
  def add_slot(subset, slot = %Slot{}, node_public_key) do
    true = :ets.insert(@table_name, {subset, {slot, node_public_key}})
    backup_slot(slot, node_public_key)
  end

  defp recover_path(), do: Utils.mut_dir("slot_backup")

  defp backup_slot(slot, node_public_key) do
    content = serialize(slot, node_public_key)

    recover_path()
    |> File.write!(content, [:append, :binary])
  end

  defp recover_slots() do
    if File.exists?(recover_path()) do
      next_summary_time = DateTime.utc_now() |> SummaryTimer.next_summary() |> DateTime.to_unix()

      content = File.read!(recover_path())

      deserialize(content, [])
      |> Enum.each(fn
        {summary_time, slot = %Slot{subset: subset}, node_public_key} ->
          if summary_time == next_summary_time,
            do: true = :ets.insert(@table_name, {subset, {slot, node_public_key}})

        # Backward compatibility
        {summary_time, slot = %Slot{subset: subset}} ->
          if summary_time == next_summary_time,
            do: true = :ets.insert(@table_name, {subset, slot})
      end)
    else
      :ok
    end
  end

  defp serialize(slot = %Slot{slot_time: slot_time}, node_public_key) do
    summary_time = SummaryTimer.next_summary(slot_time) |> DateTime.to_unix()
    slot_bin = Slot.serialize(slot) |> Utils.wrap_binary()
    slot_size = byte_size(slot_bin) |> VarInt.from_value()

    <<summary_time::32, slot_size::binary, slot_bin::binary, node_public_key::binary>>
  end

  defp deserialize(<<>>, acc), do: acc

  defp deserialize(rest, acc) do
    <<summary_time::32, rest::binary>> = rest
    {slot_size, rest} = VarInt.get_value(rest)
    <<slot_bin::binary-size(slot_size), rest::binary>> = rest
    {slot, _} = Slot.deserialize(slot_bin)

    # Backward compatibility
    try do
      {node_public_key, rest} = Utils.deserialize_public_key(rest)
      deserialize(rest, [{summary_time, slot, node_public_key} | acc])
    catch
      _ ->
        deserialize(rest, [{summary_time, slot} | acc])
    end
  end
end
