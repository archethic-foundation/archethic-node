defmodule UnirisCore.CryptoSupervisor do
  @moduledoc false
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    keystore = Application.get_env(:uniris_core, UnirisCore.Crypto)[:keystore]

    children =
      [
        UnirisCore.Crypto.LibSodiumPort,
        keystore
      ] ++ configurable_children()

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp configurable_children() do
    [
      configure(UnirisCore.Crypto.TransactionLoader)
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
