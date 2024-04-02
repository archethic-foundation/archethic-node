import Config

config :logger, level: System.get_env("ARCHETHIC_LOGGER_LEVEL", "debug") |> String.to_atom()

if System.get_env("ARCHETHIC_FILE_LOGGER", "false") == "true" do
  config :logger,
    backends: [:console, {LoggerFileBackend, :error_log}],
    format: "[$level] $message\n"

  config :logger, :error_log,
    path: "_build/dev/lib/archethic/aelog.txt",
    level: :debug
end

config :archethic,
       :mut_dir,
       System.get_env(
         "ARCHETHIC_MUT_DIR",
         "data_#{System.get_env("ARCHETHIC_CRYPTO_SEED", "node1")}"
       )

config :archethic, :root_mut_dir, System.get_env("ARCHETHIC_ROOT_MUT_DIR", "./data")

config :telemetry_poller, :default, period: 5_000

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :archethic, Archethic.BeaconChain.SlotTimer,
  # Every 10 seconds
  interval: "*/10 * * * * * *"

config :archethic, Archethic.BeaconChain.SummaryTimer,
  # Every minute
  interval: "0 * * * * * *"

config :archethic, Archethic.Bootstrap,
  reward_address: System.get_env("ARCHETHIC_REWARD_ADDRESS", "") |> Base.decode16!(case: :mixed)

config :archethic, Archethic.Bootstrap.NetworkInit,
  genesis_pools: [
    %{
      address:
        "00001259AE51A6E63A1E04E308C5E769E0E9D15BFFE4E7880266C8FA10C3ADD7B7A2"
        |> Base.decode16!(case: :mixed),
      amount: 1_000_000_000_000_000
    }
  ]

config :archethic, Archethic.Bootstrap.Sync, out_of_sync_date_threshold: 60

config :archethic, Archethic.P2P.BootstrappingSeeds,
  # First node crypto seed is "node1"
  genesis_seeds:
    System.get_env(
      "ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS",
      "127.0.0.1:3002:00011D967D71B2E135C84206DDD108B5925A2CD99C8EBC5AB5D8FD2EC9400CE3C98A:tcp"
    )

config :archethic, Archethic.Crypto, root_ca_public_keys: [software: [], tpm: []]

config :archethic, Archethic.Crypto.NodeKeystore.Origin.SoftwareImpl,
  node_seed: System.get_env("ARCHETHIC_CRYPTO_SEED", "node1")

config :archethic,
       Archethic.Crypto.NodeKeystore.Origin,
       (case System.get_env("ARCHETHIC_CRYPTO_NODE_KEYSTORE_IMPL", "SOFTWARE")
             |> String.upcase() do
          "SOFTWARE" ->
            Archethic.Crypto.NodeKeystore.Origin.SoftwareImpl

          "TPM" ->
            Archethic.Crypto.NodeKeystore.Origin.TPMImpl
        end)

config :archethic, Archethic.Governance.Pools,
  initial_members: [
    technical_council: [
      {"00011D967D71B2E135C84206DDD108B5925A2CD99C8EBC5AB5D8FD2EC9400CE3C98A", 1}
    ],
    ethical_council: [],
    foundation: [],
    uniris: []
  ]

config :archethic, Archethic.OracleChain.Scheduler,
  # Poll new changes every 10 seconds
  polling_interval: "*/10 * * * * * *",
  # Aggregate every minute
  summary_interval: "0 * * * * * *"

# -----Start-of-Networking-dev-configs-----
config :archethic, Archethic.Networking,
  validate_node_ip: System.get_env("ARCHETHIC_NODE_IP_VALIDATION", "false") == "true"

config :archethic, Archethic.Networking.IPLookup, Archethic.Networking.IPLookup.Static

config :archethic, Archethic.Networking.IPLookup.Static,
  hostname: System.get_env("ARCHETHIC_STATIC_IP", "127.0.0.1")

config :archethic, Archethic.Networking.Scheduler, interval: "0 * * * * * *"

# -----end-of-Networking-dev-configs-----

config :archethic, Archethic.Reward.Scheduler,
  # At the 30th second
  interval: "30 * * * * * *"

config :archethic, Archethic.SelfRepair.Scheduler,
  # Every minute at the 5th second
  interval: "5 * * * * * *",
  # Availability application date 5 seconds after beacon summary time
  availability_application: 10

config :archethic, Archethic.SharedSecrets.NodeRenewalScheduler,
  # At 40th second Create a new node renewal tx
  interval: "40 * * * * * *",
  # At every minute, Make use of the new node renewal tx
  application_interval: "0 * * * * * *"

config :archethic, Archethic.P2P.Listener,
  port: System.get_env("ARCHETHIC_P2P_PORT", "3002") |> String.to_integer()

config :archethic, ArchethicWeb.Explorer.FaucetController, enabled: true
config :archethic, ArchethicWeb.Explorer.FaucetRateLimiter, enabled: true

config :archethic, Archethic.TransactionChain.MemTables.PendingLedger, enabled: false
config :archethic, Archethic.TransactionChain.MemTablesLoader, enabled: false

config :archethic, Archethic.Contracts.Interpreter.Library.Common.HttpImpl,
  supported_schemes: ["https", "http"]

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with webpack to recompile .js and .css sources.
config :archethic, ArchethicWeb.Endpoint,
  explorer_url:
    URI.to_string(%URI{
      scheme: "https",
      host: System.get_env("ARCHETHIC_DOMAIN_NAME", "localhost"),
      port: System.get_env("ARCHETHIC_HTTPS_PORT", "5000") |> String.to_integer(),
      path: "/explorer"
    }),
  http: [port: System.get_env("ARCHETHIC_HTTP_PORT", "4000") |> String.to_integer()],
  server: true,
  debug_errors: true,
  check_origin: false,
  watchers: [
    # Start the esbuild watcher by calling Esbuild.install_and_run(:default, args)
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    sass: {
      DartSass,
      :install_and_run,
      [:default, ~w(--embed-source-map --source-map-urls=absolute --watch)]
    }
  ],
  https: [
    port: System.get_env("ARCHETHIC_HTTPS_PORT", "5000") |> String.to_integer(),
    cipher_suite: :strong,
    otp_app: :archethic,
    sni_fun: &ArchethicWeb.AEWeb.Domain.sni/1,
    keyfile: "priv/cert/selfsigned_key.pem",
    certfile: "priv/cert/selfsigned.pem"
  ]

config :archethic, :throttle,
  by_ip_high: [
    period: 1000,
    limit: System.get_env("ARCHETHIC_THROTTLE_IP_HIGH", "5000") |> String.to_integer()
  ],
  by_ip_low: [
    period: 1000,
    limit: System.get_env("ARCHETHIC_THROTTLE_IP_LOW", "5000") |> String.to_integer()
  ],
  by_ip_and_path: [
    period: 1000,
    limit: System.get_env("ARCHETHIC_THROTTLE_IP_AND_PATH", "5000") |> String.to_integer()
  ]

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_endpoint: "http://localhost:4318"
