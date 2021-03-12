import Config

# config :logger, handle_sasl_reports: true
config :uniris, :mut_dir, System.get_env("UNIRIS_MUT_DIR", "data1")

config :telemetry_poller, :default, period: 5_000

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :uniris, Uniris.BeaconChain.SlotTimer,
  # Every 10 seconds
  interval: "*/10 * * * * *"

config :uniris, Uniris.BeaconChain.SummaryTimer,
  # At the 58th second
  interval: "58 * * * * *"

config :uniris, Uniris.Bootstrap.Sync, out_of_sync_date_threshold: 60

config :uniris, Uniris.P2P.BootstrappingSeeds,
  # First node crypto seed is "node1"
  seeds:
    System.get_env(
      "UNIRIS_P2P_SEEDS",
      "127.0.0.1:3002:0008117DAD3A936B641106B53AF3B828940C3BC5A77F1C9BFB8AD214EF6897B000:tcp"
    )

config :uniris, Uniris.Crypto.Keystore, impl: Uniris.Crypto.SoftwareKeystore

config :uniris, Uniris.Crypto.SoftwareKeystore,
  seed: System.get_env("UNIRIS_CRYPTO_SEED", "node1")

config :uniris, Uniris.DB, impl: Uniris.DB.KeyValueImpl

config :uniris, Uniris.DB.KeyValueImpl,
  root_dir: "priv/storage/#{System.get_env("UNIRIS_CRYPTO_SEED", "node1")}"

config :uniris, Uniris.Governance.Pools,
  initial_members: [
    technical_council: [{"0008117DAD3A936B641106B53AF3B828940C3BC5A77F1C9BFB8AD214EF6897B000", 1}],
    ethical_council: ["0008117DAD3A936B641106B53AF3B828940C3BC5A77F1C9BFB8AD214EF6897B000"],
    foundation: ["0008117DAD3A936B641106B53AF3B828940C3BC5A77F1C9BFB8AD214EF6897B000"],
    uniris: ["0008117DAD3A936B641106B53AF3B828940C3BC5A77F1C9BFB8AD214EF6897B000"]
  ]

config :uniris, Uniris.OracleChain.Scheduler,
  # Poll new changes every 10 seconds
  polling_interval: "*/10 * * * * *",
  # Aggregate chain every minute
  summary_interval: "0 * * * * *"

config :uniris, Uniris.Networking.IPLookup, impl: Uniris.Networking.IPLookup.Static

config :uniris, Uniris.SelfRepair.Scheduler,
  # Every minute
  interval: "0 * * * * * *"

config :uniris, Uniris.SelfRepair.Sync,
  last_sync_file: "priv/p2p/last_sync_#{System.get_env("UNIRIS_CRYPTO_SEED", "node1")}"

config :uniris, Uniris.SelfRepair.Sync.BeaconSummaryHandler.NetworkStatistics,
  dump_dir: "priv/p2p/network_stats_#{System.get_env("UNIRIS_CRYPTO_SEED", "node1")}"

config :uniris, Uniris.SharedSecrets.NodeRenewalScheduler,
  # At 40th second
  interval: "40 * * * * * *"

config :uniris, Uniris.P2P.Endpoint,
  port: System.get_env("UNIRIS_P2P_PORT", "3002") |> String.to_integer()

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with webpack to recompile .js and .css sources.
config :uniris, UnirisWeb.Endpoint,
  http: [port: System.get_env("UNIRIS_HTTP_PORT", "4000") |> String.to_integer()],
  server: true,
  debug_errors: true,
  check_origin: false,
  watchers: [
    node: [
      "node_modules/webpack/bin/webpack.js",
      "--mode",
      "development",
      "--watch-stdin",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]
