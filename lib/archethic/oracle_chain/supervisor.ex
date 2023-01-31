defmodule Archethic.OracleChain.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.OracleChain.MemTable
  alias Archethic.OracleChain.MemTableLoader
  alias Archethic.OracleChain.Scheduler

  alias Archethic.Utils
  alias Archethic.Utils.HydratingCache

  require Logger

  @pairs ["usd", "eur"]

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args)
  end

  def init(_args) do
    scheduler_conf = Application.get_env(:archethic, Scheduler)

    ## Cook hydrating cache parameters from configuration
    uco_service_providers =
      :archethic
      |> Application.get_env(Archethic.OracleChain.Services.UCOPrice, [])
      |> Keyword.get(:providers, [])
      |> IO.inspect(label: "Providers")
      |> Enum.map(fn {mod, refresh_rate, ttl} ->
        {mod, mod, :fetch, [@pairs], refresh_rate, ttl}
      end)

    children = [
      {HydratingCache, [Archethic.Utils.HydratingCache.UcoPrice, uco_service_providers]},
      MemTable,
      MemTableLoader,
      {Scheduler, scheduler_conf}
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
