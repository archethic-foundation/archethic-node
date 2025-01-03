defmodule Migration_1_6_0 do
  @moduledoc false

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Subset.SummaryCache
  alias Archethic.BeaconChain.Subset.SummaryCacheSupervisor

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  require Logger

  def run() do
    summary_date = BeaconChain.next_summary_date(DateTime.utc_now())

    current_summary_path = Utils.mut_dir("slot_backup-#{DateTime.to_unix(summary_date)}")

    if File.exists?(current_summary_path) do
      Logger.info("Migration 1.6.0 starting slot migration")

      processes_pid = start_processes()

      current_summary_path
      |> File.read!()
      |> deserialize()
      |> tap(fn slots -> Logger.info("Migration 1.6.0 #{length(slots)} slots to migrate}") end)
      |> Task.async_stream(fn {slot, key} -> SummaryCache.add_slot(slot, key) end)
      |> Stream.run()

      maybe_stop_processes(processes_pid)

      Logger.info("Migration 1.6.0 removing old slot_backup")
      Utils.mut_dir("slot_backup-*") |> Path.wildcard() |> Enum.each(&File.rm/1)
    else
      Logger.info("Migration 1.6.0 no slot to migrate")
    end
  end

  defp start_processes() do
    {:ok, pubsub_pid} =
      case Process.whereis(Archethic.PubSubRegistry) do
        nil -> Registry.start_link(keys: :duplicate, name: Archethic.PubSubRegistry)
        _ -> {:ok, nil}
      end

    {:ok, supervisor_pid} =
      case Process.whereis(SummaryCacheSupervisor) do
        nil ->
          PartitionSupervisor.start_link(
            child_spec: SummaryCache,
            name: SummaryCacheSupervisor,
            partitions: 64
          )

        _ ->
          {:ok, nil}
      end

    {pubsub_pid, supervisor_pid}
  end

  defp maybe_stop_processes({pubsub_pid, supervisor_pid}) do
    if is_pid(supervisor_pid), do: Supervisor.stop(supervisor_pid)
    if is_pid(pubsub_pid), do: Supervisor.stop(pubsub_pid)
  end

  defp deserialize(rest, acc \\ [])
  defp deserialize(<<>>, acc), do: acc

  defp deserialize(rest, acc) do
    {slot_size, rest} = VarInt.get_value(rest)
    <<slot_bin::binary-size(slot_size), rest::binary>> = rest
    {slot, _} = Slot.deserialize(slot_bin)
    {node_public_key, rest} = Utils.deserialize_public_key(rest)
    deserialize(rest, [{slot, node_public_key} | acc])
  end
end
