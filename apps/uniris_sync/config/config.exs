import Mix.Config

config :uniris_sync, :self_repair_interval, 86_400_000

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
