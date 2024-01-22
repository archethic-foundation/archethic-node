defmodule Archethic.Telemetry do
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
      # Archethic
      distribution("archethic.election.validation_nodes.duration",
        unit: {:native, :millisecond},
        tags: [:nb_nodes],
        measurement: :duration,
        reporter_options: [
          buckets: [10, 30, 50, 100, 200, 500, 1000, 2000]
        ]
      ),
      distribution("archethic.election.storage_nodes.duration",
        unit: {:native, :millisecond},
        tags: [:nb_nodes],
        measurement: :duration,
        reporter_options: [
          buckets: [10, 30, 50, 100, 200, 500, 1000, 2000]
        ]
      ),
      distribution("archethic.mining.proof_of_work.duration",
        unit: {:native, :millisecond},
        tags: [:nb_keys],
        measurement: :duration,
        reporter_options: [
          buckets: [10, 30, 50, 100, 200, 500, 1000, 2000]
        ]
      ),
      distribution(
        "archethic.mining.pending_transaction_validation.duration",
        unit: {:native, :millisecond},
        measurement: :duration,
        reporter_options: [
          buckets: [10, 30, 50, 100, 200, 500, 1000, 2000]
        ]
      ),
      distribution("archethic.mining.fetch_context.duration",
        unit: {:native, :millisecond},
        measurement: :duration,
        reporter_options: [
          buckets: [10, 30, 50, 100, 200, 500, 1000, 2000]
        ]
      ),
      distribution(
        "archethic.mining.full_transaction_validation.duration",
        unit: {:native, :millisecond},
        measurement: :duration,
        reporter_options: [
          buckets: [500, 700, 1000, 1500, 2000, 3000, 5000, 10000]
        ]
      ),
      distribution("archethic.contract.parsing.duration",
        unit: {:native, :millisecond},
        measurement: :duration,
        reporter_options: [
          buckets: [10, 30, 50, 100, 200, 500, 1000, 2000]
        ]
      ),
      distribution(
        "archethic.transaction_end_to_end_validation.duration",
        unit: {:native, :millisecond},
        measurement: :duration,
        reporter_options: [
          buckets: [500, 700, 1000, 1500, 2000, 3000, 5000, 10000]
        ]
      ),
      distribution("archethic.p2p.send_message.duration",
        unit: {:native, :millisecond},
        measurement: :duration,
        reporter_options: [
          buckets: [10, 50, 100, 200, 300, 500, 700, 1000, 1500, 2000, 3000, 5000]
        ],
        tags: [:message]
      ),
      distribution("archethic.p2p.handle_message.duration",
        unit: {:native, :millisecond},
        measurement: :duration,
        reporter_options: [buckets: [10, 30, 50, 100, 200, 500, 1000, 2000]],
        tags: [:message]
      ),
      distribution("archethic.p2p.encode_message.duration",
        unit: {:native, :millisecond},
        measurement: :duration,
        reporter_options: [buckets: [10, 30, 50, 100, 200, 500, 1000, 2000]],
        tags: [:message]
      ),
      distribution("archethic.p2p.decode_message.duration",
        unit: {:native, :millisecond},
        measurement: :duration,
        reporter_options: [buckets: [10, 30, 50, 100, 200, 500, 1000, 2000]],
        tags: [:message]
      ),
      distribution("archethic.p2p.transport_sending_message.duration",
        unit: {:native, :millisecond},
        measurement: :duration,
        reporter_options: [buckets: [10, 30, 50, 100, 200, 500, 1000, 2000]],
        tags: [:message]
      ),
      distribution("archethic.crypto.tpm_sign.duration",
        unit: {:native, :millisecond},
        measurement: :duration,
        reporter_options: [
          buckets: [10, 50, 100, 200, 300, 500, 700, 900, 1000, 1500, 2000, 3000]
        ]
      ),
      distribution("archethic.crypto.libsodium.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [10, 30, 50, 100, 200, 500, 1000, 2000, 5000]],
        measurement: :duration
      ),
      distribution("archethic.crypto.encrypt.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [10, 30, 50, 100, 200, 500, 1000, 2000, 5000]],
        measurement: :duration
      ),
      distribution("archethic.crypto.decrypt.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [10, 30, 50, 100, 200, 500, 1000, 2000, 5000]],
        measurement: :duration
      ),
      distribution("archethic.replication.validation.duration",
        unit: {:native, :millisecond},
        reporter_options: [
          buckets: [10, 30, 50, 100, 200, 500, 1000, 2000]
        ],
        measurement: :duration
      ),
      distribution("archethic.replication.full_write.duration",
        unit: {:native, :millisecond},
        reporter_options: [
          buckets: [10, 30, 50, 100, 200, 500, 1000, 2000, 5000]
        ],
        measurement: :duration
      ),
      distribution("archethic.db.duration",
        unit: {:native, :millisecond},
        reporter_options: [
          buckets: [10, 30, 50, 100, 200, 500, 1000, 2000]
        ],
        measurement: :duration,
        tags: [:query]
      ),
      last_value("archethic.self_repair.duration",
        unit: {:native, :millisecond},
        measurement: :duration
      ),
      distribution("archethic.self_repair.process_aggregate.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [1000, 5000, 10000, 30000, 60000, 120_000, 300_000, 600_000]],
        measurement: :duration,
        tags: [:nb_transactions]
      ),
      distribution("archethic.self_repair.fetch_and_aggregate_summaries.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [10, 100, 200, 500, 700, 1000, 2000, 3000, 5000, 10000]],
        measurement: :duration
      ),
      distribution("archethic.self_repair.summaries_fetch.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [10, 100, 200, 500, 700, 1000, 2000, 3000, 5000, 10000]],
        measurement: :duration,
        tags: [:nb_summaries]
      ),
      counter("archethic.self_repair.resync.count", tags: [:network_chain]),
      distribution("archethic.beacon_chain.network_coordinates.compute_patch.duration",
        unit: {:native, :millisecond},
        reporter_options: [
          buckets: [
            10,
            25,
            50,
            100,
            300,
            500,
            800,
            1000,
            1500,
            2000,
            5000,
            10000,
            20000,
            35000,
            60000
          ]
        ],
        measurement: :duration,
        tags: [:matrix_size]
      ),
      distribution("archethic.beacon_chain.network_coordinates.collect_stats.duration",
        unit: {:native, :millisecond},
        reporter_options: [
          buckets: [
            10,
            25,
            50,
            100,
            300,
            500,
            800,
            1000,
            1500,
            2000,
            5000,
            10000,
            20000,
            35000,
            60000
          ]
        ],
        measurement: :duration,
        tags: [:matrix_size]
      ),

      # Archethic Web
      counter("archethic_web.hosting.cache_file.hit.count"),
      counter("archethic_web.hosting.cache_file.miss.count"),
      counter("archethic_web.hosting.cache_ref_tx.hit.count"),
      counter("archethic_web.hosting.cache_ref_tx.miss.count")
    ]
  end
end
