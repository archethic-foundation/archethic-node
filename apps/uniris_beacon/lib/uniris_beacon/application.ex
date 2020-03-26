defmodule UnirisBeacon.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    :ets.new(:beacon_cache, [:set, :named_table, :public])
    subsets = Enum.map(0..254, &:binary.encode_unsigned(&1))
    :ets.insert(:beacon_cache, {:subsets, subsets})

    children =
      [
        {Registry, keys: :unique, name: UnirisBeacon.SubsetRegistry, partitions: System.schedulers_online()}
      ] ++ subset_processes(subsets)


    opts = [strategy: :one_for_one, name: UnirisBeacon.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp subset_processes(subsets) do
    Enum.map(subsets, fn subset ->
      Supervisor.child_spec(
        {UnirisBeacon.Subset,
         subset: subset,
         slot_interval: Application.get_env(:uniris_beacon, :slot_interval)},
        id: subset
      )
    end)
  end
end
