defmodule Uniris.Telemetry do
  @moduledoc false

  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp periodic_measurements do
    [
      {:process_info,
       event: [:uniris, :processes, :info], name: Uniris.Application, keys: [:memory]}
    ]
  end

  def metrics do
    [
      last_value("vm.memory.binary", unit: :byte),
      counter("vm.memory.total")
    ]
  end
end
