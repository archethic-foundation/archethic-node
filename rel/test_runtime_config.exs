import Config

config :uniris, UnirisCore.P2P.Endpoint,
  port: 40_000

config :uniris, UnirisWeb.Endpoint,
  http: [:inet6, port: 8888 |> String.to_integer()],
  url: [host: "*", port: 8888]

config :uniris, Uniris.P2P.BootstrapingSeeds,
  seeds: System.get_env("UNIRIS_P2P_SEEDS")

config :uniris, Uniris.Storage, Uniris.Storage.FileBackend

config :uniris, Uniris.Crypto.SoftwareKeystore,
  seed: System.get_env("UNIRIS_CRYPTO_SEED")