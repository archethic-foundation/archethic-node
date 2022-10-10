defmodule Mix.Tasks.Archethic.Migrate do
  @moduledoc "Handle data migration"

  use Mix.Task

  alias Archethic.BeaconChain.Summary
  alias Archethic.BeaconChain.SummaryAggregate

  alias Archethic.DB.EmbeddedImpl
  alias Archethic.DB.EmbeddedImpl.ChainWriter

  def run(_arg) do
    :archethic
    |> Application.spec(:vsn)
    |> List.to_string()
    |> migrate()
  end

  def migrate("0.25.0") do
    ChainWriter.base_beacon_path(EmbeddedImpl.db_path())
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
      Map.update(acc, summary_time, %SummaryAggregate{summary_time: summary_time}, fn aggregate ->
        aggregate
        |> SummaryAggregate.add_summary(summary, false)
      end)
    end)
    |> Enum.map(fn {_, summary_aggregate} -> SummaryAggregate.aggregate(summary_aggregate) end)
    |> Enum.each(fn aggregate ->
      EmbeddedImpl.write_beacon_summaries_aggregate(aggregate)
    end)
  end

  def migrate(_), do: :ok
end
