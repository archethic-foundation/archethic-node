defmodule Archethic.Utils.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    children = [
      {Registry, keys: :unique, name: Archethic.Utils.LockWorkerRegistry}
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
