defmodule UnirisWeb.Application do
  @moduledoc false

  use Application

  alias UnirisWeb.Endpoint

  def start(_type, _args) do
    children = [
      # Start the endpoint when the application starts
      Endpoint,
      {Absinthe.Subscription, Endpoint},
      UnirisWeb.TransactionSubscriber
    ]

    opts = [strategy: :one_for_one, name: UnirisWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end
end
