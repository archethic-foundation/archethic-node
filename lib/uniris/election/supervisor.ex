defmodule Uniris.ElectionSupervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.Election.Constraints

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      Constraints
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
