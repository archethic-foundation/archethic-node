defmodule Archethic.Metrics.ETSFlush do
  @moduledoc """
  This module is used to regularly flush ETS of any buffered distribution
  type metrics (see https://github.com/beam-telemetry/telemetry_metrics_prometheus_core/blob/main/lib/core.ex#L25-L28)
  for more information.
  """

  alias TelemetryMetricsPrometheus.Core

  use GenServer
  @vsn 1

  def start_link(arg \\ []) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    timer = schedule_flush()
    {:ok, %{timer: timer}}
  end

  def handle_info(:flush, state) do
    Core.scrape()
    timer = schedule_flush()
    {:noreply, Map.put(state, :timer, timer)}
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, 5_000)
  end
end
