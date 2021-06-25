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
        "mix credo --strict",
        "mix test --trace",
        "mix dialyzer"
      ]
    ]
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$date $time $metadata[$level] $message\n",
  metadata: [:request_id, :proposal_address, :transaction, :beacon_subset, :node, :address],
  colors: [enabled: true]

config :logger,
  utc_log: true,
  handle_otp_reports: true,
  handle_sasl_reports: false

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :archethic, :src_dir, File.cwd!()

config :archethic, :mut_dir, "data"

config :archethic, :marker, "-=%=-=%=-=%=-"

config :archethic, ArchEthic.Crypto,
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
  key_certificates_dir: System.get_env("ARCHETHIC_CRYPTO_CERT_DIR", "~/key_certificates")

config :archethic, ArchEthic.Crypto.NodeKeystore.SoftwareImpl,
  seed: System.get_env("ARCHETHIC_CRYPTO_SEED")

config :archethic, ArchEthic.DB, ArchEthic.DB.CassandraImpl

config :archethic, ArchEthic.Bootstrap.NetworkInit,
  genesis_seed:
    <<226, 4, 212, 129, 254, 162, 178, 168, 206, 139, 176, 91, 179, 29, 83, 20, 50, 98, 0, 25,
      133, 242, 197, 73, 199, 53, 46, 127, 7, 223, 45, 246>>,
  genesis_daily_nonce_seed:
    <<190, 107, 211, 23, 6, 230, 228, 144, 253, 154, 200, 213, 66, 172, 229, 96, 5, 171, 134, 249,
      80, 160, 149, 4, 106, 249, 155, 116, 186, 125, 77, 192>>

config :archethic, ArchEthic.P2P.BootstrappingSeeds,
  backup_file: "p2p/seeds",
  genesis_seeds: System.get_env("ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS")

config :archethic, ArchEthic.P2P.Endpoint,
  nb_acceptors: 100,
  transport: :tcp,
  port: 3002

config :archethic, ArchEthic.SelfRepair.Sync, last_sync_file: "p2p/last_sync"

# Configure the endpoint
config :archethic, ArchEthicWeb.Endpoint,
  secret_key_base: "5mFu4p5cPMY5Ii0HvjkLfhYZYtC0JAJofu70bzmi5x3xzFIJNlXFgIY5g8YdDPMf",
  render_errors: [view: ArchEthicWeb.ErrorView, accepts: ~w(json)],
  pubsub_server: ArchEthicWeb.PubSub,
  live_view: [
    signing_salt: "3D6jYvx3",
    layout: {ArchEthicWeb.LayoutView, "live.html"}
  ]

config :archethic, ArchEthic.Bootstrap.NetworkInit,
  genesis_pools: [
    funding: [
      public_key: "000004D1E769768AA6ABE40E9D04BD5AF5D5E0CACFB50C250455AD95222D54644721",
      amount: 3.82e9
    ],
    deliverable: [
      public_key: "0000D8F54BEDBBB3BAEC8A0680F816886E9B12C2000A382BADE92B2FD0E4474BBBF0",
      amount: 2.36e9
    ],
    enhancement: [
      public_key: "0000E5225BBA00C651A55CFDBA3F1A39861FB57A3052477B465ABA8FFAD9E732577D",
      amount: 9.0e8
    ],
    team: [
      public_key: "0000857C0A211D1D4186C9D639E3A2AE8A2F112118298ECF574BD346176537780B1B",
      amount: 5.6e8
    ],
    exchange: [
      public_key: "0000BDC880BCA2AF01FDDB12816D9410E1A429FD07D37ECBD24097334143D4BD144F",
      amount: 3.4e8
    ],
    marketing: [
      public_key: "0000BC759DBEE4972D169D7CD3C550C825DC38B0580572B9AAE8ABE44319FD995439",
      amount: 3.4e8
    ],
    foundation: [
      public_key: "0000240B3822D15985542549EE697F3FF186807C13C01184D19C648C5725FC3F81F7",
      amount: 2.2e8
    ]
  ]

config :archethic, ArchEthic.Mining, timeout: 3_000

config :archethic, ArchEthic.OracleChain,
  services: [
    uco: ArchEthic.OracleChain.Services.UCOPrice
  ]

config :archethic, ArchEthic.OracleChain.Services.UCOPrice,
  provider: ArchEthic.OracleChain.Services.UCOPrice.Providers.Coingecko

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
