defmodule ArchEthic.SelfRepair.Supervisor do
  @moduledoc false

  use Supervisor

  alias ArchEthic.SelfRepair.Notifier
  alias ArchEthic.SelfRepair.Scheduler

  alias ArchEthic.Utils

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {Scheduler, Application.get_env(:archethic, Scheduler)},
      Notifier
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
