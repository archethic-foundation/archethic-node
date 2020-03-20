import Mix.Config

# Self repair every day
config :uniris_sync, :self_repair_interval, 86_400_000

# Beacon subset wrap transaction creation every 10 min
config :uniris_sync, :beacon_slot_interval, 600_000

