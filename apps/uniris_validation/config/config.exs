import Mix.Config

config :uniris_validation, :P2P_client, UnirisP2P.SupervisedConnection

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
