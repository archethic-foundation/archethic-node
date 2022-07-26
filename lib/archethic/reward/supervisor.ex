defmodule Archethic.Reward.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.Reward.Scheduler

  alias Archethic.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: Archethic.RewardSupervisor)
  end

  def init(_) do
    children = [
      {Scheduler, Application.get_env(:archethic, Scheduler)}
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
