defmodule UnirisSync.Beacon.Supervisor do
  @moduledoc false

  use Supervisor

  alias UnirisSync.Beacon.Subset

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    slot_interval = Keyword.get(opts, :slot_interval)
    startup_date = Keyword.get(opts, :startup_date)
    subsets = Keyword.get(opts, :subsets)

    children =
      subsets
      |> Enum.map(fn subset ->
        Supervisor.child_spec(
          {Subset, subset: subset, slot_interval: slot_interval, startup_date: startup_date},
          id: subset
        )
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end

end
