defmodule Archethic.Contracts.Wasm.Result do
  @moduledoc """
  Represents a result which mutate the transaction or state
  """
  @type t :: %__MODULE__{
          ok: %{value: term()} | nil,
          error: String.t() | nil
        }

  @derive Jason.Encoder
  defstruct [:ok, :error]

  def wrap_ok(value) do
    %__MODULE__{ok: %{value: value}}
  end

  def wrap_error(message) do
    %__MODULE__{error: message}
  end
end

defmodule Archethic.Contracts.Wasm.UpdateResult do
  @moduledoc """
  Represents a result which mutate the transaction or state
  """
  @type t :: %__MODULE__{
          state: map(),
          transaction: map()
        }
  defstruct [:state, :transaction]
end

defmodule Archethic.Contracts.Wasm.ReadResult do
  @moduledoc """
  Represents a result which doesn't mutate
  """
  @type t :: %__MODULE__{
          value: any()
        }
  defstruct [:value]
end

defmodule Archethic.Contracts.WasmResult do
  @moduledoc """
  Represents a WebAssembly module return
  """
  alias Archethic.Contracts.Wasm.UpdateResult
  alias Archethic.Contracts.Wasm.ReadResult

  @doc """
  Cast JSON WebAssembly result in `UpdateResult` or `ReadResult`
  """
  @spec cast(map() | nil) :: UpdateResult.t() | ReadResult.t()
  def cast(result) when is_map_key(result, "state") or is_map_key(result, "transaction") do
    %UpdateResult{
      state: Map.get(result, "state") |> cast_state(),
      transaction: result |> Map.get("transaction") |> cast_transaction()
    }
  end

  def cast(result), do: %ReadResult{value: result}

  defp cast_state(nil), do: %{}
  defp cast_state(state), do: state

  defp cast_transaction(nil), do: nil

  defp cast_transaction(%{
         "type" => type,
         "data" => tx_data
       }) do
    %{
      type: type,
      data: Archethic.Utils.atomize_keys(tx_data)
    }
  end
end
