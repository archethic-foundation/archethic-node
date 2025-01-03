defmodule Archethic.BeaconChain.Subset.SummaryCache do
  @moduledoc """
  Handle the caching of the beacon slots defined for the summary
  """

  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Subset.SummaryCacheSupervisor
  alias Archethic.BeaconChain.SummaryTimer
  alias Archethic.Crypto

  alias Archethic.PubSub

  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  use GenServer
  @vsn 2

  @batch_read_size 102_400

  def start_link(arg \\ []) do
    GenServer.start_link(__MODULE__, arg)
  end

  def init(_) do
    PubSub.register_to_current_epoch_of_slot_time()
    PubSub.register_to_node_status()

    {:ok, %{}}
  end

  def code_change(_version, state, _extra), do: {:ok, state}

  def handle_info({:current_epoch_of_slot_timer, slot_time}, state) do
    if SummaryTimer.match_interval?(slot_time), do: delete_old_backup_file(slot_time)

    {:noreply, state}
  end

  def handle_info(:node_up, state) do
    previous_summary_time = SummaryTimer.previous_summary(DateTime.utc_now())
    delete_old_backup_file(previous_summary_time)

    {:noreply, state}
  end

  def handle_info(:node_down, state), do: {:noreply, state}

  @doc """
  Stream all the transaction summaries
  """
  @spec stream_summaries(DateTime.utc_now(), pos_integer()) ::
          list(TransactionSummary.t())
  def stream_summaries(summary_time, subset) do
    summary_time
    |> stream_slots(subset)
    |> Stream.flat_map(fn {%Slot{transaction_attestations: attestations}, _} -> attestations end)
    |> Stream.map(& &1.transaction_summary)
  end

  @doc """
  Add new beacon slots to the summary's cache
  """
  @spec add_slot(Slot.t(), Crypto.key()) :: :ok
  def add_slot(slot = %Slot{subset: subset}, node_public_key) do
    via_tuple = {:via, PartitionSupervisor, {SummaryCacheSupervisor, subset}}
    GenServer.call(via_tuple, {:add_slot, slot, node_public_key})
  end

  def handle_call({:add_slot, slot, node_public_key}, _from, state) do
    backup_slot(slot, node_public_key)
    {:reply, :ok, state}
  end

  defp delete_old_backup_file(previous_summary_time) do
    # We keep 2 backup, the current one and the last one

    previous_backup_path = recover_path(previous_summary_time)

    Utils.mut_dir("slot_backup/*")
    |> Path.wildcard()
    |> Enum.filter(&(&1 < previous_backup_path))
    |> Enum.each(&File.rm_rf/1)
  end

  defp recover_path(summary_time = %DateTime{}) do
    timestamp = DateTime.to_unix(summary_time)
    "slot_backup" |> Path.join("#{timestamp}") |> Utils.mut_dir()
  end

  defp recover_path(summary_time = %DateTime{}, subset),
    do: summary_time |> recover_path() |> Path.join(Base.encode16(subset))

  defp backup_slot(slot = %Slot{slot_time: slot_time, subset: subset}, node_public_key) do
    content = serialize(slot, node_public_key)

    summary_time =
      if SummaryTimer.match_interval?(slot_time),
        do: slot_time,
        else: SummaryTimer.next_summary(slot_time)

    summary_time |> recover_path() |> File.mkdir_p!()
    summary_time |> recover_path(subset) |> File.write!(content, [:append, :binary])
  end

  @spec stream_slots(DateTime.t(), subset :: binary) ::
          Enumerable.t() | list({slot :: Slot.t(), node_public_key :: Crypto.key()})
  def stream_slots(summary_time, subset) do
    backup_file_path = recover_path(summary_time, subset)

    if File.exists?(backup_file_path) do
      backup_file_path
      |> File.stream!([], @batch_read_size)
      |> Stream.transform(<<>>, fn content, rest ->
        deserialize(<<rest::bitstring, content::bitstring>>)
      end)
    else
      []
    end
  end

  defp serialize(slot, node_public_key) do
    slot_bin = Slot.serialize(slot) |> Utils.wrap_binary()
    slot_size = byte_size(slot_bin) |> VarInt.from_value()

    <<slot_size::binary, slot_bin::binary, node_public_key::binary>>
  end

  defp deserialize(rest, acc \\ [])
  defp deserialize(<<>>, acc), do: {Enum.reverse(acc), <<>>}

  defp deserialize(rest, acc) do
    with {slot_size, rest} <- VarInt.get_value(rest),
         <<slot_bin::binary-size(slot_size), rest::binary>> <- rest,
         {slot, _} = Slot.deserialize(slot_bin),
         {node_public_key, rest} <- Utils.deserialize_public_key(rest) do
      deserialize(rest, [{slot, node_public_key} | acc])
    else
      _ ->
        # This happens when the content is not a complete entry
        {acc, rest}
    end
  end
end
