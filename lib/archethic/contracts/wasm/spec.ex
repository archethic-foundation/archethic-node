defmodule Archethic.Contracts.WasmSpec do
  alias Archethic.Contracts.WasmTrigger

  defstruct [:version, triggers: [], public_functions: [], upgrade_opts: nil]

  def cast(%{
        "version" => version,
        "triggers" => triggers,
        "publicFunctions" => public_functions,
        "upgradeOpts" => upgrade_opts
      }) do
    %__MODULE__{
      version: version,
      triggers: Enum.map(triggers, &WasmTrigger.cast/1),
      public_functions: public_functions,
      upgrade_opts: __MODULE__.UpgradeOpts.cast(upgrade_opts)
    }
  end

  defmodule UpgradeOpts do
    defstruct [:from]

    def cast(%{"from" => from}) do
      %__MODULE__{from: Base.decode16!(from, case: :mixed)}
    end

    def cast(nil), do: nil
  end
end
