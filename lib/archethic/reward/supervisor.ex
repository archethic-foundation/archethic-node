defmodule Archethic.Reward.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.Utils
  alias Archethic.Reward.Scheduler
  alias Archethic.Reward.MemTablesLoader
  alias Archethic.Reward.MemTables.RewardTokens

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: Archethic.RewardSupervisor)
  end

  def init(_) do
    children = [
      {Scheduler, Application.get_env(:archethic, Scheduler)},
      RewardTokens,
      MemTablesLoader
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :rest_for_one)
  end
end
