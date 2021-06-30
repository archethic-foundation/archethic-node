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
  key_certificates_dir: System.get_env("ARCHETHIC_CRYPTO_CERT_DIR", "~/aebot/key_certificates")

config :archethic, ArchEthic.Crypto.NodeKeystore.SoftwareImpl,
  seed: System.get_env("ARCHETHIC_CRYPTO_SEED")

config :archethic, ArchEthic.DB, ArchEthic.DB.CassandraImpl

config :archethic, ArchEthic.Bootstrap.NetworkInit,
  genesis_seed:
    <<226, 4, 212, 129, 254, 162, 178, 168, 206, 139, 176, 91, 179, 29, 83, 20, 50, 98, 0, 25,
      133, 242, 197, 73, 199, 53, 46, 127, 7, 223, 45, 246>>,
  genesis_daily_nonce_seed:
    <<190, 107, 211, 23, 6, 230, 228, 144, 253, 154, 200, 213, 66, 172, 229, 96, 5, 171, 134, 249,
      80, 160, 149, 4, 106, 249, 155, 116, 186, 125, 77, 192>>,
  genesis_origin_public_keys: [
    "010004AB41291F847A601055AEDD1AF24FF76FA970D6441E2DCA3818A8319B004C96B27B8FEB1DA31A044BA0A4800B4353359735719EBB3A05F98393A9CC599C3FAFD6"
    |> Base.decode16!(case: :mixed)
  ]

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
      public_key:
        "010004491dbeb3dbe9f327ef53e795416f7fdd7742ffd4fccd66f0dab1b113126440794786b3fdb46ecee0fac324b29de3d996d2a1bbc3b798440dbc4dd963eab92342",
      amount: 3.82e9
    ],
    deliverable: [
      public_key:
        "010004133f933e55e0af85afb21f60f3f63bf5baa56da65f36646e8c8a7e190032a0d3628823aa552d7b8d8659c6ecdeeef453bfabcff65f2a84ea332b02335465505f",
      amount: 2.36e9
    ],
    enhancement: [
      public_key:
        "01000426cf0a186023b7ad87f98f274d58ff20f3f8eb65fd649be5939e2bd1b30b724aafb59ac36abb148c508d1c607478b782ee4c5de88a9213aaa563651c476d9917",
      amount: 9.0e8
    ],
    team: [
      public_key:
        "010004bfaa4157ce34f0960044e35ed6705e25bb020875e9e72e43f6b56dcd4284a40909c0932cb3dfb45027133196f50509db2b12ab06ae04038bb46adbb302c37e50",
      amount: 5.6e8
    ],
    exchange: [
      public_key:
        "01000428ba2913c5eccddeb744fccc927fc14fa428991edb5ad6ff5910b8f963cad4fa936c7ff82b2aeef1feaf3e98adab0aaed93329b129f29f17110239d1f4aeae07",
      amount: 3.4e8
    ],
    marketing: [
      public_key:
        "010004ba4c68d3ddddf61fefb11c707c18a966c6b77a71c55aee22817e1839ad10f069eb713a375e466b05468a4aef12115cafefade9816b5195d09f41b1b87b54fe15",
      amount: 3.4e8
    ],
    foundation: [
      public_key:
        "01000480ee3cf265a170ef78defb2db50990800cafe30c7d006f55d55f2b8908a2855a710a46707800eb7dfaf64d9a014689e37c772fb2a4e9dd22ce9c11ce6b674a49",
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
