defmodule Archethic.Networking.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.Networking.Scheduler
  alias Archethic.Utils

  def start_link(arg \\ []) do
    Supervisor.start_link(__MODULE__, arg, name: Archethic.NetworkingSupervisor)
  end

  def init(_arg) do
    children = [
      {Scheduler, Application.get_env(:archethic, Scheduler)}
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
