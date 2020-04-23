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
  default_hash: :sha256,
  seed: "fake seed",
  keystore: UnirisCore.Crypto.SoftwareKeystore

config :uniris_core, UnirisCore.Crypto.TransactionLoader, enabled: false

config :uniris_core, UnirisCore.Storage, backend: UnirisCore.Storage.FileBackend

config :uniris_core, UnirisCore.P2P,
  port: 3005,
  node_client: MockNodeClient

config :uniris_core, UnirisCore.P2P.TransactionLoader, enabled: false

config :uniris_core, UnirisCore.Beacon, slot_interval: 1000
config :uniris_core, UnirisCore.BeaconSubset, enabled: false

config :uniris_core, UnirisCore.SharedSecrets.TransactionLoader, enabled: false

config :uniris_core, UnirisCore.SharedSecrets.NodeRenewal,
  interval: 0,
  trigger_interval: 0,
  enabled: false

config :uniris_core, UnirisCore.SelfRepair, enabled: false

config :uniris_core, UnirisCore.Bootstrap,
  seeds_file: "priv/p2p/seeds",
  ip_lookup_provider: MockIPLookup,
  enabled: false
