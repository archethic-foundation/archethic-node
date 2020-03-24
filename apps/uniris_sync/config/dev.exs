import Mix.Config

# Self repair every min
config :uniris_sync, :self_repair_interval, 5_000

# Beacon slot creation every 10 seconds
config :uniris_sync, :beacon_slot_interval, 5_000

config :uniris_sync, :last_sync_date, DateTime.utc_now()

config :uniris_sync, :public_ip_provider, UnirisSync.Bootstrap.IPLookup.EnvImpl
