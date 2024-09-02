defmodule Archethic.Contracts.WasmIO.NetworkImpl do
  @moduledoc """
  Represent I/O function for WebAssembly contract a real network
  """

  @behaviour Archethic.Contracts.WasmIO

  def get_balance(address) do
    Archethic.get_balance(address)
  end
end
