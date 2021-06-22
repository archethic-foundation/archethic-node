defmodule ArchEthic.Reward.Supervisor do
  @moduledoc false

  use Supervisor

  alias ArchEthic.Reward.NetworkPoolScheduler

  alias ArchEthic.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: ArchEthic.RewardSupervisor)
  end

  def init(_) do
    children = [
      {NetworkPoolScheduler, Application.get_env(:archethic, NetworkPoolScheduler)}
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
