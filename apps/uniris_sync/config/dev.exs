import Mix.Config

# Self repair every 30s
config :uniris_sync, :self_repair_interval, 30_000

config :uniris_sync, :last_sync_date, DateTime.utc_now()

config :uniris_sync, :ip_provider, UnirisSync.Bootstrap.IPLookup.EnvImpl


