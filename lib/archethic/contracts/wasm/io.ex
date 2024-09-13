defmodule Archethic.Contracts.Wasm.IO do
  @moduledoc """
  Query some data of the blockchain from the SC
  """
  alias Archethic.Contracts.Wasm.Result

  defmodule Request do
    @moduledoc false

    @type t :: %{
            method: String.t(),
            params: term()
          }
    defstruct [:method, :params]
  end

  use Knigge, otp_app: :archethic, default: __MODULE__.JSONRPCImpl
  @callback request(request :: Request.t()) :: Result.t()
end
