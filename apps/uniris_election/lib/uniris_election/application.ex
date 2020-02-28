defmodule UnirisElection.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {UnirisElection.DefaultImpl.HypergeometricDistribution,
       [
         executable: Application.app_dir(:uniris_election, "/priv/c/hypergeometric_distribution")
       ]}
    ]

    opts = [strategy: :one_for_one, name: UnirisElection.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
