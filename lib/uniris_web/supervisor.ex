defmodule UnirisWeb.Supervisor do
  @moduledoc false

  use Supervisor

  alias UnirisWeb.Endpoint
  alias UnirisWeb.TransactionSubscriber

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    children = [
      # Start the endpoint when the application starts
      Endpoint,
      {Absinthe.Subscription, Endpoint},
      TransactionSubscriber
    ]

    opts = [strategy: :one_for_one, name: UnirisWeb.Supervisor]
    Supervisor.init(children, opts)
  end
end
