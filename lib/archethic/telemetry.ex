defmodule ArchEthic.Telemetry do
  @moduledoc false

  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    [
      {TelemetryMetricsPrometheus.Core, [metrics: metrics()]}
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end

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
      last_value("vm.total_run_queue_lengths.io"),
      # Phoenix
      summary("phoenix.router_dispatch.stop.duration", unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.exception.duration", unit: {:native, :millisecond}),
      summary("phoenix.socket_connected.duration", unit: {:native, :millisecond}),
      summary("phoenix.channel_joined.duration", unit: {:native, :millisecond}),
      summary("phoenix.channel_handled_in.duration", unit: {:native, :millisecond}),
      summary("phoenix.error_rendered.duration", unit: {:native, :millisecond}),
      # Plug
      summary("plug_adapter.call.stop.duration", unit: {:native, :millisecond}),
      summary("plug_adapter.call.exception.duration", unit: {:native, :millisecond}),
      # Absinth
      summary("absinthe.middleware.batch.stop", unit: {:native, :millisecond}),
      summary("absinthe.resolve.field.stop", unit: {:native, :millisecond}),
      summary("absinthe.execute.operation.stop", unit: {:native, :millisecond}),
      summary("absinthe.subscription.publish.stop", unit: {:native, :millisecond}),
      # ArchEthic
      summary("archethic.election.validation_nodes.duration", unit: {:native, :millisecond}),
      summary("archethic.election.storage_nodes.duration", unit: {:native, :millisecond}),
      summary("archethic.mining.proof_of_work.duration", unit: {:native, :millisecond}),
      summary("archethic.mining.pending_transaction_validation.duration",
        unit: {:native, :millisecond}
      ),
      summary("archethic.mining.fetch_context.duration", unit: {:native, :millisecond}),
      summary("archethic.mining.full_transaction_validation.duration",
        unit: {:native, :millisecond}
      ),
      summary("archethic.contract.parsing.duration", unit: {:native, :millisecond}),
      summary("archethic.transaction_end_to_end_validation.duration", unit: {:native, :millisecond}),
      summary("archethic.p2p.send_message.duration", unit: {:native, :millisecond}),
      summary("archethic.crypto.tpm_sign.duration", unit: {:native, :millisecond})
    ]
  end
end
