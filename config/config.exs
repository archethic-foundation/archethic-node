use Mix.Config

config :git_hooks,
  auto_install: true,
  verbose: true,
  hooks: [
    pre_commit: [
      tasks: [
        "mix clean",
        "mix format --check-formatted"
      ]
    ],
    pre_push: [
      tasks: [
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
  metadata: [:request_id, :proposal_address, :transaction, :beacon_subset, :node]

config :logger,
  utc_log: true,
  handle_otp_reports: true,
  handle_sasl_reports: false

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :uniris, :src_dir, File.cwd!()

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
      133, 242, 197, 73, 199, 53, 46, 127, 7, 223, 45, 246>>

config :uniris, Uniris.P2P.BootstrappingSeeds, file: "priv/p2p/seeds"

config :uniris, Uniris.P2P.Endpoint,
  port: System.get_env("UNIRIS_P2P_PORT", "3002") |> String.to_integer(),
  nb_acceptors: 10,
  transport: :tcp

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

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
