defmodule Uniris.Oracles.Supervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.Oracles.{
    Scheduler,
    UcoPrice
  }

  alias Uniris.Utils

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    optional_children = [
      {Scheduler, [mfa: {UcoPrice, :fetch, []}, interval: "0 * * * * * *"], id: :uco_price}
    ]

    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :one_for_one)
  end

  @spec get_state() :: [map()]
  def get_state do
    Supervisor.which_children(__MODULE__)
    |> Enum.map(fn {_id, pid, :worker, _modules} -> Scheduler.get_payload(pid) end)
  end
end
