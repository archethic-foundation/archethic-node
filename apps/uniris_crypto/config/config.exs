use Mix.Config

config :uniris_crypto, :supported_curves, [
  :ed25519,
  :secp256r1,
  :secp256k1
]

config :uniris_crypto, :supported_hashes, [
  :sha256,
  :sha512,
  :sha3_256,
  :sha3_512,
  :blake2b
]

config :uniris_crypto, :default_curve, :ed25519
config :uniris_crypto, :default_hash, :sha256

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
