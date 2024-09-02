defmodule Archethic.Contracts.WasmIO do
  @moduledoc """
  Represents callbacks for WebAssembly contract to performs I/O operations
  """

  alias Archethic.UTXO

  use Knigge, otp_app: :archethic, default: __MODULE__.NetworkImpl
  @callback get_balance(address :: binary()) :: UTXO.balance()
end
