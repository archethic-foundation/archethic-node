use Mix.Config

config :uniris_chain,
       :genesis_daily_nonce,
       <<159, 30, 62, 26, 143, 247, 217, 224, 199, 38, 221, 246, 52, 48, 129, 199, 167, 24, 81,
         204, 178, 192, 128, 72, 167, 120, 26, 102, 230, 40, 165, 68>>

config :uniris_chain, :genesis_origin_public_keys, [

]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
