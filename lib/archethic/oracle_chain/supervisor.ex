defmodule Archethic.OracleChain.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.OracleChain.MemTable
  alias Archethic.OracleChain.MemTableLoader
  alias Archethic.OracleChain.Scheduler

  alias Archethic.Utils

  alias ArchethicCache.HydratingCache

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args)
  end

  def init(_args) do
    scheduler_conf = Application.get_env(:archethic, Scheduler)

    children =
      [
        MemTable,
        MemTableLoader,
        {Scheduler, scheduler_conf}
      ] ++ self_hydrating_caches()

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end

  # all oracle services should use a self-hydrating cache
  defp self_hydrating_caches() do
    Application.get_env(:archethic, Archethic.OracleChain, [])
    |> Keyword.get(:services, [])
    |> Keyword.values()
    |> Enum.map(fn service_module ->
      # we expect a list of providers in config for each services
      providers =
        Application.get_env(:archethic, service_module, [])
        |> Keyword.get(:providers, [])

      {HydratingCache, [service_module, providers]}
    end)
  end
end
