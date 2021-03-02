defmodule Uniris.Election.Supervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.Election.Constraints
  alias Uniris.Election.HypergeometricDistribution

  alias Uniris.Utils

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    optional_children = [
      {Constraints, [], []},
      {HypergeometricDistribution, [], []}
    ]

    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
