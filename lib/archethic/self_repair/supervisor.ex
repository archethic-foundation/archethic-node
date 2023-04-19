defmodule Archethic.SelfRepair.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.SelfRepair.NetworkView
  alias Archethic.SelfRepair.Scheduler
  alias Archethic.Utils

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {Scheduler, Application.get_env(:archethic, Scheduler)},
      {DynamicSupervisor, strategy: :one_for_one, name: Archethic.SelfRepair.NotifierSupervisor},
      NetworkView
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
