defmodule ArchEthic.Telemetry do
  @moduledoc false

  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    [{TelemetryMetricsPrometheus.Core, [metrics: metrics() ++ more_metrics()]}]
    |> Supervisor.init(strategy: :one_for_one)
  end

  @distr unit: {:native, :millisecond}, reporter_options: [buckets: [1, 2, 3]]

  def metrics do
    [
      # VM
      last_value("vm.memory.atom", unit: :byte),
      last_value("vm.memory.atom_used", unit: :byte),
      last_value("vm.memory.binary", unit: :byte),
      last_value("vm.memory.code", unit: :byte),
      last_value("vm.memory.ets", unit: :byte),
      last_value("vm.memory.processes", unit: :byte),
      last_value("vm.memory.processes_used", unit: :byte),
      last_value("vm.memory.system", unit: :byte),
      last_value("vm.memory.total", unit: :byte),
      #
      last_value("vm.system_counts.atom_count"),
      last_value("vm.system_counts.port_count"),
      last_value("vm.system_counts.process_count"),
      #
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io")
    ]
  end

  def more_metrics do
    [
      # Phoenix
      distribution("phoenix.router_dispatch.stop.duration", @distr),
      distribution("phoenix.router_dispatch.exception.duration", @distr),
      distribution("phoenix.socket_connected.duration", @distr),
      distribution("phoenix.channel_joined.duration", @distr),
      distribution("phoenix.channel_handled_in.duration", @distr),
      distribution("phoenix.error_rendered.duration", @distr),
      # Plug
      distribution("plug_adapter.call.stop.duration", @distr),
      distribution("plug_adapter.call.exception.duration", @distr),
      # Absinth
      distribution("absinthe.middleware.batch.stop", @distr),
      distribution("absinthe.resolve.field.stop", @distr),
      distribution("absinthe.execute.operation.stop", @distr),
      distribution("absinthe.subscription.publish.stop", @distr),
      # Dataloader
      distribution("dataloader.source.run.stop", @distr),
      distribution("dataloader.source.batch.run.stop", @distr)
    ]
  end
end
