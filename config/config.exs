import Config

config :git_hooks,
  auto_install: true,
  verbose: true,
  hooks: [
    pre_push: [
      tasks: [
        {:cmd, "mix clean"},
        {:cmd, "mix format --check-formatted"},
        {:cmd, "mix compile --warnings-as-errors"},
        {:cmd, "mix credo"},
        {:cmd, "mix sobelow"},
        {:cmd, "mix knigge.verify"},
        {:cmd, "mix test --trace"},
        {:cmd, "mix dialyzer"},
        {:cmd, "mix check.updates"}
      ]
    ]
  ]

# Configures Elixir's Logger
config :logger,
  utc_log: true,
  handle_otp_reports: true,
  handle_sasl_reports: false

config :logger, :console,
  format: "$date $time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :proposal_address,
    :transaction_address,
    :transaction_type,
    :beacon_subset,
    :node,
    :address,
    :message_id,
    :replication_roles,
    :contract
  ],
  colors: [enabled: true]

# Faucet rate limit in Number of transactions
config :archethic, :faucet_rate_limit, 3

# Faucet rate limit Expiry time in milliseconds
config :archethic, :faucet_rate_limit_expiry, 3_600_000

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Set nx backend to EXLA
config :nx, default_backend: EXLA.Backend

config :archethic, :src_dir, File.cwd!()

config :archethic, :mut_dir, "data"

config :archethic, :marker, "-=%=-=%=-=%=-"

# size represents in bytes binary
config :archethic, :transaction_data_content_max_size, 3_145_728

# size represents in bytes binary
# 24KB Max
config :archethic, :transaction_data_code_max_size, 24576

config :archethic, Archethic.Crypto,
  supported_curves: [
    :ed25519,
    :secp256r1,
    :secp256k1
  ],
  supported_hashes: [
    :sha256,
    :sha512,
    :sha3_256,
    :sha3_512,
    :blake2b
  ],
  default_curve: :ed25519,
  default_hash: :sha256,
  storage_nonce_file: "crypto/storage_nonce",
  key_certificates_dir: System.get_env("ARCHETHIC_CRYPTO_CERT_DIR", "~/aebot/key_certificates")

config :archethic, Archethic.DB, Archethic.DB.EmbeddedImpl
config :archethic, Archethic.UTXO.DBLedger, Archethic.UTXO.DBLedger.FileImpl

config :archethic, Archethic.Bootstrap.NetworkInit,
  genesis_seed:
    <<226, 4, 212, 129, 254, 162, 178, 168, 206, 139, 176, 91, 179, 29, 83, 20, 50, 98, 0, 25,
      133, 242, 197, 73, 199, 53, 46, 127, 7, 223, 45, 246>>,
  genesis_daily_nonce_seed:
    <<190, 107, 211, 23, 6, 230, 228, 144, 253, 154, 200, 213, 66, 172, 229, 96, 5, 171, 134, 249,
      80, 160, 149, 4, 106, 249, 155, 116, 186, 125, 77, 192>>,
  genesis_origin_public_keys: [
    "010104AB41291F847A601055AEDD1AF24FF76FA970D6441E2DCA3818A8319B004C96B27B8FEB1DA31A044BA0A4800B4353359735719EBB3A05F98393A9CC599C3FAFD6"
    |> Base.decode16!(case: :mixed)
  ],
  genesis_network_pool_amount: 34_441_853 * 100_000_000

config :archethic, Archethic.P2P.BootstrappingSeeds,
  backup_file: "p2p/seeds",
  genesis_seeds: System.get_env("ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS")

config :archethic, Archethic.P2P.Listener,
  nb_acceptors: 100,
  transport: :tcp,
  port: 3002

# Floor upload speed in bytes/sec (1Mb/sec -> 0.125MB/s)
config :archethic, Archethic.P2P.Message, floor_upload_speed: 125_000

config :archethic, Archethic.SelfRepair.Sync, last_sync_file: "p2p/last_sync"

# Default cachae size for the chain index is 300MB
config :archethic,
       Archethic.DB.ChainIndex.MaxCacheSize,
       String.to_integer(System.get_env("ARCHETHIC.CHAIN_INDEX_MAX_CACHE_SIZE", "300000000"))

config :archethic, Archethic.UTXO.MemoryLedger, [
  # Default threshold size for the utxo input into memory is around 50KB
  # For an average of UTXO: ~ 650B (token's type) to have 100 inputs, it represents 65KB
  # To reach around 1GB of cache for this memory table, we can target around 15 000 genesis's input into memory
  size_threshold: String.to_integer(System.get_env("ARCHETHIC.UTXO_SIZE_THRESHOLD", "50000"))
]

# Configure the endpoint
config :archethic, ArchethicWeb.Endpoint,
  secret_key_base: "5mFu4p5cPMY5Ii0HvjkLfhYZYtC0JAJofu70bzmi5x3xzFIJNlXFgIY5g8YdDPMf",
  render_errors: [view: ArchethicWeb.Explorer.ErrorView, accepts: ~w(json)],
  pubsub_server: ArchethicWeb.PubSub,
  live_view: [
    signing_salt: "3D6jYvx3",
    layout: {ArchethicWeb.Explorer.LayoutView, "live.html"}
  ]

config :archethic, Archethic.Mining.StandaloneWorkflow, global_timeout: 10_000

config :archethic, Archethic.Mining.DistributedWorkflow,
  global_timeout: 60_000,
  coordinator_timeout_supplement: 2_000,
  context_notification_timeout: 3_000

config :archethic, Archethic.OracleChain,
  services: [
    uco: Archethic.OracleChain.Services.UCOPrice
  ]

config :archethic, Archethic.OracleChain.Services.UCOPrice,
  providers: %{
    # Coingecko limits to 10-30 calls, with 30s delay we would be under the limitation
    Archethic.OracleChain.Services.UCOPrice.Providers.Coingecko => [refresh_interval: 30_000],
    Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCapArchethic => [
      refresh_interval: 30_000
    ],
    # Coinpaprika limits to 25K req/mo; with 2min delay we can reach ~21K
    Archethic.OracleChain.Services.UCOPrice.Providers.CoinPaprika => [refresh_interval: 120_000]
  }

config :archethic, ArchethicWeb.Explorer.FaucetController,
  seed:
    "3A7B579DBFB7CEBE26293850058F180A65D6A3D2F6964543F5EDE07BEB2EFDA4"
    |> Base.decode16!(case: :mixed)

# -----Start-of-Networking-configs-----

config :archethic, Archethic.Networking.IPLookup.NATDiscovery,
  provider: Archethic.Networking.IPLookup.NATDiscovery.MiniUPNP

config :archethic, Archethic.Networking.IPLookup.RemoteDiscovery,
  provider: Archethic.Networking.IPLookup.RemoteDiscovery.IPIFY

config :archethic, Archethic.Networking.PortForwarding, port_range: 49_152..65_535
# -----End-of-Networking-configs ------

config :archethic, ArchethicWeb.AEWeb.WebHostingController,
  # The tx_cache is stored on RAM
  # 750MB should hold a minimum 250 transactions
  tx_cache_bytes: 750 * 1024 * 1024,

  # The file_cache is stored on DISK
  # 5GB should hold 2000 average size pages
  # https://httparchive.org/reports/page-weight
  file_cache_bytes: 5 * 1024 * 1024 * 1024

config :esbuild,
  version: "0.12.18",
  default: [
    args: ~w(js/app.js --bundle --target=es2018 --outdir=../priv/static/js),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :dart_sass,
  version: "1.54.5",
  default: [
    args: ~w(css/app.scss --load-path=node_modules ../priv/static/css/app.css),
    cd: Path.expand("../assets", __DIR__)
  ]

config :ex_cldr,
  default_locale: "en",
  default_backend: Archethic.Cldr,
  json_library: Jason

config :ex_json_schema, :remote_schema_resolver, {Archethic.Utils, :local_schema_resolver!}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config("#{Mix.env()}.exs")
