# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

# Configures the endpoint
config :uniris_web, UnirisWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "5mFu4p5cPMY5Ii0HvjkLfhYZYtC0JAJofu70bzmi5x3xzFIJNlXFgIY5g8YdDPMf",
  render_errors: [view: UnirisWeb.ErrorView, accepts: ~w(json)],
  pubsub: [name: UnirisWeb.PubSub, adapter: Phoenix.PubSub.PG2],
  live_view: [
    signing_salt: "3D6jYvx3",
    layout: {UnirisWeb.LayoutView, "live.html"}
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
