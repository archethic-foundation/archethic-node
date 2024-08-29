defmodule Archethic.Contracts.WasmSpec do
  @moduledoc false

  alias Archethic.Contracts.WasmTrigger

  @type t :: %__MODULE__{
          version: pos_integer(),
          triggers: list(WasmTrigger.t()),
          public_functions: list(String.t()),
          upgrade_opts: nil | __MODULE__.UpgradeOpts.t()
        }
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
    @moduledoc false

    @type t :: %__MODULE__{
            from: binary()
          }
    defstruct [:from]

    def cast(%{"from" => from}) do
      %__MODULE__{from: Base.decode16!(from, case: :mixed)}
    end

    def cast(nil), do: nil
  end
end
