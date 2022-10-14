import Config

config :git_hooks,
  auto_install: true,
  verbose: true,
  hooks: [
    pre_push: [
      tasks: [
        "mix clean",
        "mix format --check-formatted",
        "mix compile --warnings-as-errors",
        "mix credo",
        "mix sobelow",
        "mix knigge.verify",
        "mix test --trace",
        "mix dialyzer"
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
  genesis_network_pool_amount: 3_340_000_000_000_000

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

# Configure the endpoint
config :archethic, ArchethicWeb.Endpoint,
  secret_key_base: "5mFu4p5cPMY5Ii0HvjkLfhYZYtC0JAJofu70bzmi5x3xzFIJNlXFgIY5g8YdDPMf",
  render_errors: [view: ArchethicWeb.ErrorView, accepts: ~w(json)],
  pubsub_server: ArchethicWeb.PubSub,
  live_view: [
    signing_salt: "3D6jYvx3",
    layout: {ArchethicWeb.LayoutView, "live.html"}
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
  provider: Archethic.OracleChain.Services.UCOPrice.Providers.Coingecko

config :archethic, ArchethicWeb.FaucetController,
  seed:
    "3A7B579DBFB7CEBE26293850058F180A65D6A3D2F6964543F5EDE07BEB2EFDA4"
    |> Base.decode16!(case: :mixed)

# -----Start-of-Networking-configs-----

config :archethic, Archethic.Networking.IPLookup.NATDiscovery,
  provider: Archethic.Networking.IPLookup.NATDiscovery.MiniUPNP

config :archethic, Archethic.Networking.IPLookup.RemoteDiscovery,
  provider: Archethic.Networking.IPLookup.RemoteDiscovery.IPIFY

# -----End-of-Networking-configs ------

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config("#{Mix.env()}.exs")
