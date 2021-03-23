defmodule Uniris.Reward.Supervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.Reward.NetworkPoolScheduler
  alias Uniris.Reward.WithdrawScheduler

  alias Uniris.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: Uniris.RewardSupervisor)
  end

  def init(_) do
    children = [
      {NetworkPoolScheduler, Application.get_env(:uniris, NetworkPoolScheduler)},
      {WithdrawScheduler, Application.get_env(:uniris, WithdrawScheduler)}
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
