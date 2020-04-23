defmodule UnirisCore.BeaconSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: UnirisBeaconSupervisor)
  end

  def init(_opts) do
    subsets = Enum.map(0..254, &:binary.encode_unsigned(&1))

    slot_interval =
      :uniris_core
      |> Application.get_env(UnirisCore.Beacon)
      |> Keyword.fetch!(:slot_interval)

    children =
      [
        {Registry, keys: :unique, name: UnirisCore.BeaconSubsetRegistry},
        {UnirisCore.BeaconSubsets, subsets},
        {UnirisCore.BeaconSlotTimer, slot_interval: slot_interval}
      ] ++ configurable_children(subsets, slot_interval)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp configurable_children(subsets, slot_interval) do
    Enum.map(subsets, fn subset ->
      configure(UnirisCore.BeaconSubset, [subset: subset, slot_interval: slot_interval],
        id: subset
      )
    end)
    |> List.flatten()
  end

  defp configure(process, args, opts) do
    if should_start?(process) do
      Supervisor.child_spec({process, args}, opts)
    else
      []
    end
  end

  defp should_start?(process) do
    :uniris_core
    |> Application.get_env(process, enabled: true)
    |> Keyword.fetch!(:enabled)
  end
end
