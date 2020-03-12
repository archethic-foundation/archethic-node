use Mix.Config

config :uniris_crypto, :seed, System.get_env("UNIRIS_CRYPTO_SEED", :crypto.strong_rand_bytes(32))
