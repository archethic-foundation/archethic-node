import Mix.Config

config :uniris_network, :p2p_client, UnirisP2P

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
