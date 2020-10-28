import Config

config :uniris, Uniris.P2P.Endpoint,
  port: 40_000

config :uniris, UnirisWeb.Endpoint,
  http: [:inet6, port: String.to_integer(8888)],
  url: [host: "*", port: 8888]

config :uniris, Uniris.P2P.BootstrappingSeeds,
  seeds: System.get_env("UNIRIS_P2P_SEEDS")

config :uniris, Uniris.DB, impl: Uniris.DB.KeyValueImpl

config :uniris, Uniris.Crypto.Keystore, impl: Uniris.Crypto.SoftwareKeystore
config :uniris, Uniris.Crypto.SoftwareKeystore,
  seed: System.get_env("UNIRIS_CRYPTO_SEED")