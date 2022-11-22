defmodule Mix.Tasks.Archethic.Migrate do
  @moduledoc "Handle data migration"

  use Mix.Task

  alias Archethic.BeaconChain.Summary
  alias Archethic.BeaconChain.SummaryAggregate

  alias Archethic.DB.EmbeddedImpl
  alias Archethic.DB.EmbeddedImpl.ChainWriter

  def run(_arg) do
    version =
      :archethic
      |> Application.spec(:vsn)
      |> List.to_string()

    file_path = EmbeddedImpl.db_path() |> ChainWriter.migration_file_path()

    migration_done? =
      if File.exists?(file_path) do
        file_path |> File.read!() |> String.split(";") |> Enum.member?(version)
      else
        File.touch!(file_path)
        true
      end

    unless migration_done? do
      migrate(version)

      File.write!(file_path, "#{version};", [:append])
    end
  end

  def migrate("0.25.0") do
    db_path = EmbeddedImpl.db_path()
    File.mkdir_p!(ChainWriter.base_beacon_aggregate_path(db_path))

    ChainWriter.base_beacon_path(db_path)
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.map(fn file ->
      {summary, _} =
        file
        |> File.read!()
        |> Summary.deserialize()

      summary
    end)
    |> Enum.reduce(%{}, fn summary = %Summary{summary_time: summary_time}, acc ->
      Map.update(
        acc,
        summary_time,
        %SummaryAggregate{summary_time: summary_time},
        &SummaryAggregate.add_summary(&1, summary, false)
      )
    end)
    |> Enum.map(fn {_, summary_aggregate} -> SummaryAggregate.aggregate(summary_aggregate) end)
    |> Enum.each(fn aggregate = %SummaryAggregate{summary_time: summary_time} ->
      filepath = ChainWriter.beacon_aggregate_path(db_path, summary_time)

      unless File.exists?(filepath) do
        EmbeddedImpl.write_beacon_summaries_aggregate(aggregate)
      end
    end)
  end

  def migrate("0.27.0") do
    db_path = EmbeddedImpl.db_path()
    file_path = Path.join(db_path, "p2p_view")

    if File.exists?(file_path) do
      fd = File.open!(file_path, [:binary, :read])
      nodes_view = load_from_file_0_27_0(fd)
      nodes_view_bin = serialize_0_27_0(nodes_view, <<>>)
      File.write!(file_path, nodes_view_bin, [:binary])
    end
  end

  def migrate(_), do: :ok

  defp load_from_file_0_27_0(fd, acc \\ %{}) do
    with {:ok, <<public_key_size::8>>} <- :file.read(fd, 1),
         {:ok,
          <<public_key::binary-size(public_key_size), timestamp::32, available::8,
            avg_availability::8>>} <- :file.read(fd, public_key_size + 6) do
      available? = if available == 1, do: true, else: false

      case Map.get(acc, public_key) do
        nil ->
          load_from_file_0_27_0(
            fd,
            Map.put(acc, public_key, %{
              available?: available?,
              avg_availability: avg_availability / 100,
              timestamp: timestamp
            })
          )

        %{timestamp: prev_timestamp} when timestamp > prev_timestamp ->
          load_from_file_0_27_0(
            fd,
            Map.put(acc, public_key, %{
              available?: available?,
              avg_availability: avg_availability / 100,
              timestamp: timestamp
            })
          )

        _ ->
          load_from_file_0_27_0(fd, acc)
      end
    else
      :eof ->
        Enum.map(acc, fn {node_public_key,
                          %{available?: available?, avg_availability: avg_availability}} ->
          {node_public_key, available?, avg_availability, DateTime.utc_now()}
        end)
    end
  end

  defp serialize_0_27_0([], acc), do: acc

  defp serialize_0_27_0([view | rest], acc) do
    {node_key, available?, avg_availability, availability_update} = view

    available_bit = if available?, do: 1, else: 0
    avg_availability_int = (avg_availability * 100) |> trunc()

    acc =
      <<acc::bitstring, node_key::binary, available_bit::8, avg_availability_int::8,
        DateTime.to_unix(availability_update)::32>>

    serialize_0_27_0(rest, acc)
  end
end
