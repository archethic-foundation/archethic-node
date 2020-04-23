defmodule UnirisCore.SharedSecretsSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children =
      [
        UnirisCore.SharedSecrets.Cache
      ] ++ configurable_children()

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp configurable_children() do
    renewal_trigger_interval =
      :uniris_core
      |> Application.get_env(UnirisCore.SharedSecrets.NodeRenewal)
      |> Keyword.fetch!(:trigger_interval)

    [
      configure(UnirisCore.SharedSecrets.NodeRenewal, [interval: renewal_trigger_interval], []),
      configure(UnirisCore.SharedSecrets.TransactionLoader)
    ]
    |> List.flatten()
  end

  defp configure(process, args \\ [], opts \\ []) do
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
