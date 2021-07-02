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
      distribution("phoenix.router_dispatch.stop.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.01, 0.05, 0.1, 0.2, 0.5, 1.0, 1.5, 2.0]]
      ),
      distribution("phoenix.router_dispatch.exception.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.01, 0.05, 0.1, 0.2, 0.5, 1.0, 1.5, 2.0]]
      ),
      distribution("phoenix.socket_connected.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.01, 0.05, 0.1, 0.2, 0.5, 1.0, 1.5, 2.0]]
      ),
      distribution("phoenix.channel_joined.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.01, 0.05, 0.1, 0.2, 0.5, 1.0, 1.5, 2.0]]
      ),
      distribution("phoenix.channel_handled_in.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.01, 0.05, 0.1, 0.2, 0.5, 1.0, 1.5, 2.0]]
      ),
      distribution("phoenix.error_rendered.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.01, 0.05, 0.1, 0.2, 0.5, 1.0, 1.5, 2.0]]
      ),
      # Plug
      distribution("plug_adapter.call.stop.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.01, 0.05, 0.1, 0.2, 0.5, 1.0, 1.5, 2.0]]
      ),
      distribution("plug_adapter.call.exception.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.01, 0.05, 0.1, 0.2, 0.5, 1.0, 1.5, 2.0]]
      ),
      # ArchEthic
      distribution("archethic.election.validation_nodes.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.01, 0.025, 0.05, 0.1, 0.2, 0.5, 1]]
      ),
      distribution("archethic.election.storage_nodes.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.01, 0.025, 0.05, 0.1, 0.2, 0.5, 1]]
      ),
      distribution("archethic.mining.proof_of_work.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.01, 0.025, 0.05, 0.1, 0.2, 0.5, 1]],
        tags: [:nb_keys]
      ),
      distribution(
        "archethic.mining.pending_transaction_validation.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.01, 0.025, 0.05, 0.1, 0.2, 0.5, 1]]
      ),
      distribution("archethic.mining.fetch_context.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.05, 0.1, 0.2, 0.5, 1]]
      ),
      distribution(
        "archethic.mining.full_transaction_validation.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.1, 0.5, 0.8, 1, 1.2, 1.5, 2, 2.5, 3, 5, 10]]
      ),
      distribution("archethic.contract.parsing.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.01, 0.05, 0.1, 0.2, 0.5, 1]]
      ),
      distribution(
        "archethic.transaction_end_to_end_validation.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.5, 0.8, 1, 1.5, 2, 2.5, 3.5, 5, 10]]
      ),
      distribution("archethic.p2p.send_message.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.1, 0.2, 0.5, 0.8, 1.0]],
        tags: [:message]
      ),
      distribution("archethic.crypto.tpm_sign.duration",
        unit: {:native, :second},
        measurement: :duration,
        reporter_options: [buckets: [0.1, 0.2, 0.3, 0.4, 0.5, 1]]
      ),
      distribution("archethic.replication.validation.duration",
        unit: {:native, :second},
        reporter_options: [buckets: [0.1, 0.3, 0.5, 0.8, 1, 1.5]],
        measurement: :duration
      ),
      distribution("archethic.db.duration",
        unit: {:native, :second},
        reporter_options: [buckets: [0.1, 0.3, 0.5, 0.8, 1, 1.5]],
        measurement: :duration,
        tags: [:query]
      )
    ]
  end
end
