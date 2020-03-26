import Mix.Config

# Self repair every day
config :uniris_sync, :self_repair_interval, 86_400_000

config :uniris_sync, :ip_provider, UnirisSync.Bootstrap.IPLookup.IPFYImpl
