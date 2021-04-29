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

config :uniris, :src_dir, File.cwd!()

config :uniris, :mut_dir, "data"

config :uniris, :marker, "-=%=-=%=-=%=-"

config :uniris, Uniris.Crypto,
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
  storage_nonce_file: "priv/crypto/storage_nonce"

config :uniris, Uniris.Bootstrap.NetworkInit,
  genesis_seed:
    <<226, 4, 212, 129, 254, 162, 178, 168, 206, 139, 176, 91, 179, 29, 83, 20, 50, 98, 0, 25,
      133, 242, 197, 73, 199, 53, 46, 127, 7, 223, 45, 246>>,
  genesis_daily_nonce_seed:
    <<190, 107, 211, 23, 6, 230, 228, 144, 253, 154, 200, 213, 66, 172, 229, 96, 5, 171, 134, 249,
      80, 160, 149, 4, 106, 249, 155, 116, 186, 125, 77, 192>>

config :uniris, Uniris.P2P.BootstrappingSeeds, file: "priv/p2p/seeds"

config :uniris, Uniris.P2P.Endpoint,
  nb_acceptors: 100,
  transport: :tcp,
  port: 3002

# Configure the endpoint
config :uniris, UnirisWeb.Endpoint,
  secret_key_base: "5mFu4p5cPMY5Ii0HvjkLfhYZYtC0JAJofu70bzmi5x3xzFIJNlXFgIY5g8YdDPMf",
  render_errors: [view: UnirisWeb.ErrorView, accepts: ~w(json)],
  pubsub_server: UnirisWeb.PubSub,
  live_view: [
    signing_salt: "3D6jYvx3",
    layout: {UnirisWeb.LayoutView, "live.html"}
  ]

config :uniris, Uniris.Governance.Code.CICD, impl: Uniris.Governance.Code.CICD.Docker

config :uniris, Uniris.Bootstrap.NetworkInit,
  genesis_pools: [
    funding: [
      public_key: "00203715A9B952F78980410CC9789C964DC5B38C2A0E75B8E82A5FAEF023421CA3",
      amount: 3.82e9
    ],
    deliverable: [
      public_key: "00D08385B699612DA5E2C5F4151031E043F7C866EA5DC3834087F0D2D7260DEEA7",
      amount: 2.36e9
    ],
    enhancement: [
      public_key: "002322E9BA757DB74FE1514134428F76F40BA2776386A81309E5FB99B863EAF32B",
      amount: 9.0e8
    ],
    team: [
      public_key: "009A23901D8509A3CB5203CD2BFF9F7895DCF02D2D8441BE1ED061CCD8028086DE",
      amount: 5.6e8
    ],
    exchange: [
      public_key: "00A77F32486DB6003777509BFC57CFBB86BD5357136D0602B8578A679E19A42516",
      amount: 3.4e8
    ],
    marketing: [
      public_key: "00D09EC59417BAD9DB56906BE1611CAE2B13B3F836BBE6CB4F883B0CD9241640C7",
      amount: 3.4e8
    ],
    foundation: [
      public_key: "00C5CED72549140342A8FCCF6F861C881481B982BFFD451A0F5FF43EFC179B3E7E",
      amount: 2.2e8
    ]
  ]

config :uniris, Uniris.OracleChain,
  services: [
    uco: Uniris.OracleChain.Services.UCOPrice
  ]

config :uniris, Uniris.OracleChain.Services.UCOPrice,
  provider: Uniris.OracleChain.Services.UCOPrice.Providers.Coingecko

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
