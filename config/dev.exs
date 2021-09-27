import Config

config :logger, level: System.get_env("ARCHETHIC_LOGGER_LEVEL", "debug") |> String.to_atom()

config :archethic,
       :mut_dir,
       System.get_env(
         "ARCHETHIC_MUT_DIR",
         "data_#{System.get_env("ARCHETHIC_CRYPTO_SEED", "node1")}"
       )

config :telemetry_poller, :default, period: 5_000

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :archethic, ArchEthic.BeaconChain.SlotTimer,
  # Every 10 seconds
  interval: "*/10 * * * * *"

config :archethic, ArchEthic.BeaconChain.SummaryTimer,
  # Every minute
  interval: "0 * * * * *"

config :archethic, ArchEthic.Bootstrap,
  reward_address:
    System.get_env(
      "ARCHETHIC_REWARD_ADDRESS",
      Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>)
    )
    |> Base.decode16!(case: :mixed)

config :archethic, ArchEthic.Bootstrap.NetworkInit,
  genesis_pools: [
    %{
      address:
        "00EC64107CA604A6B954037CFA91ED18315A77A94FBAFD91275CEE07FA45EAF893"
        |> Base.decode16!(case: :mixed),
      amount: 1_000_000_000_000_000
    }
  ]

config :archethic, ArchEthic.Bootstrap.Sync, out_of_sync_date_threshold: 60

config :archethic, ArchEthic.P2P.BootstrappingSeeds,
  # First node crypto seed is "node1"
  genesis_seeds:
    System.get_env(
      "ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS",
      "127.0.0.1:3002:00001D967D71B2E135C84206DDD108B5925A2CD99C8EBC5AB5D8FD2EC9400CE3C98A:tcp"
    )

config :archethic,
       ArchEthic.Crypto.NodeKeystore,
       (case System.get_env("ARCHETHIC_CRYPTO_NODE_KEYSTORE_IMPL", "SOFTWARE") do
          "SOFTWARE" ->
            ArchEthic.Crypto.NodeKeystore.SoftwareImpl

          "TPM" ->
            ArchEthic.Crypto.NodeKeystore.TPMImpl
        end)

config :archethic, ArchEthic.Crypto.NodeKeystore.SoftwareImpl,
  seed: System.get_env("ARCHETHIC_CRYPTO_SEED", "node1")

config :archethic, ArchEthic.DB.CassandraImpl,
  host: System.get_env("ARCHETHIC_DB_HOST", "127.0.0.1:9042")

config :archethic, ArchEthic.Governance.Pools,
  initial_members: [
    technical_council: [
      {"00001D967D71B2E135C84206DDD108B5925A2CD99C8EBC5AB5D8FD2EC9400CE3C98A", 1}
    ],
    ethical_council: [],
    foundation: [],
    uniris: []
  ]

config :archethic, ArchEthic.OracleChain.Scheduler,
  # Poll new changes every 10 seconds
  polling_interval: "*/10 * * * * *",
  # Aggregate chain at the 50th second
  summary_interval: "0 * * * * *"

config :archethic, ArchEthic.Networking.IPLookup, ArchEthic.Networking.IPLookup.Static

config :archethic, ArchEthic.Networking.IPLookup.Static,
  hostname: System.get_env("ARCHETHIC_STATIC_IP", "127.0.0.1")

config :archethic, ArchEthic.Networking.Scheduler, interval: "0 * * * * * *"

config :archethic, ArchEthic.Reward.NetworkPoolScheduler,
  # At the 30th second
  interval: "30 * * * * *"

config :archethic, ArchEthic.Reward.WithdrawScheduler,
  # Every 10s
  interval: "*/10 * * * * *"

config :archethic, ArchEthic.SelfRepair.Scheduler,
  # Every minute at the 5th second
  interval: "5 * * * * * *"

config :archethic, ArchEthic.SharedSecrets.NodeRenewalScheduler,
  # At 40th second
  interval: "40 * * * * * *",
  application_interval: "0 * * * * * *"

config :archethic, ArchEthic.P2P.Endpoint,
  port: System.get_env("ARCHETHIC_P2P_PORT", "3002") |> String.to_integer()

config :archethic, ArchEthicWeb.FaucetController, enabled: true

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with webpack to recompile .js and .css sources.
config :archethic, ArchEthicWeb.Endpoint,
  http: [port: System.get_env("ARCHETHIC_HTTP_PORT", "4000") |> String.to_integer()],
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
