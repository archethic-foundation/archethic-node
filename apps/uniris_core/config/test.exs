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
  keystore: MockCrypto

config :uniris_core, UnirisCore.Crypto.Keystore, enabled: false
config :uniris_core, UnirisCore.Crypto.TransactionLoader, enabled: false

config :uniris_core, UnirisCore.Storage, backend: MockStorage
config :uniris_core, UnirisCore.Storage.FileBackend, enabled: false
config :uniris_core, UnirisCore.Storage.Cache, enabled: false

config :uniris_core, UnirisCore.P2P,
  port: 10_000,
  node_client: MockNodeClient

config :uniris_core, UnirisCore.P2P.TransactionLoader, enabled: false

config :uniris_core, UnirisCore.BeaconSubset, enabled: false

config :uniris_core, UnirisCore.BeaconSlotTimer, enabled: false

config :uniris_core, UnirisCore.SharedSecrets.TransactionLoader, enabled: false

config :uniris_core, UnirisCore.SharedSecrets.NodeRenewal,
  enabled: false,
  trigger_interval: 0,
  interval: 0

config :uniris_core, UnirisCore.SelfRepair,
  enabled: false,
  network_startup_date: DateTime.utc_now() |> DateTime.add(-5)

config :uniris_core, UnirisCore.Bootstrap,
  seeds_file: "priv/p2p/test_seeds",
  ip_lookup_provider: MockIPLookup,
  enabled: false

config :uniris_core, UnirisCore.Interpreter.TransactionLoader, enabled: false
