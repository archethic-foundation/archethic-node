defmodule Archethic.Release.RestartTelemetry do
  @moduledoc false

  alias Archethic.Telemetry

  use Distillery.Releases.Appup.Transform

  def up(:archethic, _v1, _v2, instructions, _opts),
    do: add_telemetry_restart(instructions)

  def up(_, _, _, instructions, _), do: instructions

  def down(_, _, _, instructions, _), do: instructions

  defp add_telemetry_restart(instructions) do
    restart_instructions = [
      {:apply, {:supervisor, :terminate_child, [Telemetry, :prometheus_metrics]}},
      {:apply, {:supervisor, :restart_child, [Telemetry, :prometheus_metrics]}},
      {:apply, {:supervisor, :terminate_child, [Telemetry, :telemetry_poller]}},
      {:apply, {:supervisor, :restart_child, [Telemetry, :telemetry_poller]}}
    ]

    instructions ++ restart_instructions
  end
end
