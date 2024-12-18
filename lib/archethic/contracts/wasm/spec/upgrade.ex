defmodule Archethic.Contracts.WasmSpec.UpgradeOpts do
  @moduledoc false

  @type t() :: %__MODULE__{
          from: binary()
        }
  defstruct [:from]

  def cast(%{"from" => from}) do
    %__MODULE__{from: Base.decode16!(from, case: :mixed)}
  end

  def cast(nil), do: nil
end
