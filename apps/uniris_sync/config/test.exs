import Mix.Config

config :uniris_p2p, :impl, MockP2P
config :uniris_validation, :impl, MockValidation

config :uniris_sync, :beacon_slot_interval, 1_000
