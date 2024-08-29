defmodule Archethic.Contracts.Wasm.UpdateResult do
  @moduledoc false
  @type t :: %__MODULE__{
          state: map(),
          transaction: map()
        }
  defstruct [:state, :transaction]
end

defmodule Archethic.Contracts.Wasm.ReadResult do
  @moduledoc false
  @type t :: %__MODULE__{
          value: any()
        }
  defstruct [:value]
end

defmodule Archethic.Contracts.WasmResult do
  @moduledoc false
  alias Archethic.Contracts.Wasm.UpdateResult
  alias Archethic.Contracts.Wasm.ReadResult

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
    atomized_tx_type =
      case type do
        249 -> :contract
        253 -> :transfer
        250 -> :data
        251 -> :token
      end

    %{
      type: atomized_tx_type,
      data:
        tx_data
        |> Archethic.Utils.atomize_keys()
        |> Archethic.Utils.hex2bin(
          keys_to_base_decode: [
            :address,
            :to,
            :token_address,
            :secret,
            :public_key,
            :encrypted_secret_key,
            :code
          ]
        )
    }
  end
end
