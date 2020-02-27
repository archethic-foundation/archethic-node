use Mix.Config

config :uniris_crypto, :seed, :crypto.strong_rand_bytes(32)
