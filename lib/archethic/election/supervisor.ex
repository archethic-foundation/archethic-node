defmodule Archethic.Election.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.Election.Constraints

  alias Archethic.Utils

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    optional_children = [
      {Constraints, [], []}
    ]

    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
