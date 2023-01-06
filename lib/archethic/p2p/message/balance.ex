defmodule Archethic.P2P.Message.Balance do
  @moduledoc """
  Represents a message with the balance of a transaction
  """
  defstruct uco: 0, token: %{}

  alias Archethic.Utils.VarInt

  @type t :: %__MODULE__{
          uco: non_neg_integer(),
          token: %{{binary(), non_neg_integer()} => non_neg_integer()}
        }

  def encode(%__MODULE__{uco: uco_balance, token: token_balances}) do
    token_balances_binary =
      token_balances
      |> Enum.reduce([], fn {{token_address, token_id}, amount}, acc ->
        [<<token_address::binary, amount::64, VarInt.from_value(token_id)::binary>> | acc]
      end)
      |> Enum.reverse()
      |> :erlang.list_to_binary()

    encoded_token_balances_length = map_size(token_balances) |> VarInt.from_value()

    <<248::8, uco_balance::64, encoded_token_balances_length::binary,
      token_balances_binary::binary>>
  end
end
