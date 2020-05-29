use Mix.Config

config :uniris_core, UnirisCore.Crypto,
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

config :uniris_core, UnirisCore.P2P,
  port: System.get_env("UNIRIS_P2P_PORT", "3002") |> String.to_integer(),
  node_client: UnirisCore.P2P.NodeTCPClient

config :uniris_core, UnirisCore.Storage, backend: UnirisCore.Storage.CassandraBackend

config :uniris_core, UnirisCore.Storage.CassandraBackend,
    nodes: ["127.0.0.1:9042"]

config :uniris_core, UnirisCore.Bootstrap, seeds_file: "priv/p2p/seeds"

# Import environment specific config. This must remain at the bottmo
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
