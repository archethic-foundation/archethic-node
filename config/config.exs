use Mix.Config

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :logger,
  utc_log: true,
  handle_otp_reports: true,
  handle_sasl_reports: false

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

if Mix.env() != :prod do
  config :git_hooks,
    auto_install: true,
    verbose: true,
    hooks: [
      pre_commit: [
        tasks: [
          "mix format",
          "mix clean",
          "mix compile --warnings-as-errors",
          "mix credo --strict",
          "mix test"
        ]
      ]
    ]
end

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
  default_hash: :sha256

config :uniris, Uniris.P2P.Endpoint,
  port: System.get_env("UNIRIS_P2P_PORT", "3002") |> String.to_integer()

config :uniris, Uniris.P2P, node_client: Uniris.P2P.TCPClient

config :uniris, Uniris.P2P.BootstrapingSeeds, file: "priv/p2p/seeds"

# Configure the endpoint
config :uniris, UnirisWeb.Endpoint,
  secret_key_base: "5mFu4p5cPMY5Ii0HvjkLfhYZYtC0JAJofu70bzmi5x3xzFIJNlXFgIY5g8YdDPMf",
  render_errors: [view: UnirisWeb.ErrorView, accepts: ~w(json)],
  pubsub: [name: UnirisWeb.PubSub, adapter: Phoenix.PubSub.PG2],
  live_view: [
    signing_salt: "3D6jYvx3",
    layout: {UnirisWeb.LayoutView, "live.html"}
  ]

# Import environment specific config. This must remain at the bottmo
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
