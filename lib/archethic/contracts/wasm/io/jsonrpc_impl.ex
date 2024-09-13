defmodule Archethic.Contracts.Wasm.IO.JSONRPCImpl do
  @moduledoc """
  Implementation of IO functions via JSONRPC serialization
  """
  alias Archethic.Contracts.Wasm.IO, as: WasmIO
  alias Archethic.Contracts.Wasm.Result

  @spec request(req :: WasmIO.Request.t()) :: Result.t()
  def request(%{method: "getBalance", params: %{address: address}}) do
    address
    |> Base.decode16!()
    |> Archethic.get_balance()
    |> Result.wrap_ok()
  end
end
