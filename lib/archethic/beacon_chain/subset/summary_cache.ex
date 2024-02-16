defmodule Archethic.BeaconChain.Subset.SummaryCache do
  @moduledoc """
  Handle the caching of the beacon slots defined for the summary
  """

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.SummaryTimer
  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.Crypto

  alias Archethic.PubSub

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  use GenServer
  @vsn 2

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

    :ok = recover_slots(SummaryTimer.next_summary(DateTime.utc_now()))

    PubSub.register_to_current_epoch_of_slot_time()
    PubSub.register_to_node_status()
    PubSub.register_to_self_repair()

    {:ok, %{}}
  end

  # update the TransactionSummary in memory
  def code_change(1, state, _extra) do
    # credo:disable-for-lines:26
    elements =
      :ets.tab2list(@table_name)
      |> Enum.map(fn {subset, {slot, node_public_key}} ->
        slot =
          Map.update!(
            slot,
            :transaction_attestations,
            fn attestations ->
              Enum.map(
                attestations,
                fn attestation = %ReplicationAttestation{transaction_summary: summary} ->
                  %ReplicationAttestation{
                    attestation
                    | transaction_summary: Map.put(summary, :genesis_address, nil)
                  }
                end
              )
            end
          )

        {subset, {slot, node_public_key}}
      end)

    :ets.delete_all_objects(@table_name)
    :ets.insert(@table_name, elements)

    {:ok, state}
  end

  def code_change(_version, state, _extra), do: {:ok, state}

  def handle_info(:self_repair_sync, state) do
    previous_summary_time = SummaryTimer.previous_summary(DateTime.utc_now())

    BeaconChain.list_subsets()
    |> Enum.each(&clean_previous_summary_slots(&1, previous_summary_time))

    {:noreply, state}
  end

  def handle_info({:current_epoch_of_slot_timer, slot_time}, state) do
    if SummaryTimer.match_interval?(slot_time), do: delete_old_backup_file(slot_time)

    {:noreply, state}
  end

  def handle_info(:node_up, state) do
    previous_summary_time = SummaryTimer.previous_summary(DateTime.utc_now())
    delete_old_backup_file(previous_summary_time)

    BeaconChain.list_subsets()
    |> Enum.each(&clean_previous_summary_slots(&1, previous_summary_time))

    {:noreply, state}
  end

  def handle_info(:node_down, state), do: {:noreply, state}

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
      fn ->
        # Fix the table to avoid "invalid continuation" error
        # source: https://www.erlang.org/doc/man/ets#safe_fixtable-2
        :ets.safe_fixtable(@table_name, true)
        :ets.select(@table_name, match_pattern, 1)
      end,
      &do_stream_current_slots/1,
      fn _ ->
        :ets.safe_fixtable(@table_name, false)
        :ok
      end
    )
  end

  defp do_stream_current_slots(:"$end_of_table") do
    {:halt, :"$end_of_table"}
  end

  defp do_stream_current_slots({slot, continuation}) do
    {slot, :ets.select(continuation)}
  end

  @doc """
  Add new beacon slots to the summary's cache
  """
  @spec add_slot(subset :: binary(), Slot.t(), Crypto.key()) :: :ok
  def add_slot(subset, slot = %Slot{}, node_public_key) do
    true = :ets.insert(@table_name, {subset, {slot, node_public_key}})
    backup_slot(slot, node_public_key)
  end

  defp delete_old_backup_file(previous_summary_time) do
    # We keep 2 backup, the current one and the last one
    previous_backup_path = recover_path(previous_summary_time)

    Utils.mut_dir("slot_backup*")
    |> Path.wildcard()
    |> Enum.filter(&(&1 < previous_backup_path))
    |> Enum.each(&File.rm/1)
  end

  defp recover_path(summary_time = %DateTime{}),
    do: Utils.mut_dir("slot_backup-#{DateTime.to_unix(summary_time)}")

  defp backup_slot(slot = %Slot{slot_time: slot_time}, node_public_key) do
    content = serialize(slot, node_public_key)

    summary_time =
      if SummaryTimer.match_interval?(slot_time),
        do: slot_time,
        else: SummaryTimer.next_summary(slot_time)

    summary_time
    |> recover_path()
    |> File.write!(content, [:append, :binary])
  end

  defp recover_slots(summary_time) do
    backup_file_path = recover_path(summary_time)

    if File.exists?(backup_file_path) do
      content = File.read!(backup_file_path)

      deserialize(content, [])
      |> Enum.each(fn {slot = %Slot{subset: subset}, node_public_key} ->
        true = :ets.insert(@table_name, {subset, {slot, node_public_key}})
      end)
    else
      :ok
    end
  end

  defp serialize(slot, node_public_key) do
    slot_bin = Slot.serialize(slot) |> Utils.wrap_binary()
    slot_size = byte_size(slot_bin) |> VarInt.from_value()

    <<slot_size::binary, slot_bin::binary, node_public_key::binary>>
  end

  defp deserialize(<<>>, acc), do: acc

  defp deserialize(rest, acc) do
    {slot_size, rest} = VarInt.get_value(rest)
    <<slot_bin::binary-size(slot_size), rest::binary>> = rest
    {slot, _} = Slot.deserialize(slot_bin)
    {node_public_key, rest} = Utils.deserialize_public_key(rest)
    deserialize(rest, [{slot, node_public_key} | acc])
  end

  defp clean_previous_summary_slots(subset, previous_summary_time) do
    subset
    |> stream_current_slots()
    |> Stream.filter(fn {%Slot{slot_time: slot_time}, _} ->
      DateTime.compare(slot_time, previous_summary_time) != :gt
    end)
    |> Stream.each(fn item ->
      :ets.delete_object(@table_name, {subset, item})
    end)
    |> Stream.run()
  end
end
