defmodule Archethic.Contracts.WasmSpec do
  @moduledoc """
  Represents a WASM Smart Contract Specification
  """

  alias __MODULE__.Function
  alias __MODULE__.Trigger
  alias __MODULE__.UpgradeOpts

  @type t :: %__MODULE__{
          version: pos_integer(),
          triggers: list(Trigger.t()),
          public_functions: list(Function.t()),
          upgrade_opts: nil | UpgradeOpts.t()
        }
  defstruct [:version, triggers: [], public_functions: [], upgrade_opts: nil]

  def from_manifest(
        manifest = %{
          "abi" => %{
            "functions" => functions
          }
        }
      ) do
    version = Map.get(manifest, "version", 1)
    upgrade_opts = Map.get(manifest, "upgrade_opts")

    Enum.reduce(functions, %__MODULE__{version: version, upgrade_opts: upgrade_opts, triggers: [], public_functions: []}, fn
      {name, function_abi = %{"type" => "action"}}, acc ->
        Map.update!(acc, :triggers, &[Trigger.cast(name, function_abi) | &1])

      {name, function_abi = %{"type" => "publicFunction"}}, acc ->
        Map.update!(acc, :public_functions, &[Function.cast(name, function_abi) | &1])
    end)
  end

  @doc """
  Return the function exposed in the spec
  """
  @spec function_names(t()) :: list(String.t())
  def function_names(%__MODULE__{triggers: triggers, public_functions: public_functions}) do
    Enum.map(triggers, & &1.name) ++ Enum.map(public_functions, & &1.name)
  end
end
