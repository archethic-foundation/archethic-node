defmodule Archethic.P2P.Message.Balance do
  @moduledoc """
  Represents a message with the balance of a transaction
  """
  defstruct [:last_chain_sync_date, uco: 0, token: %{}]

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  @type t :: %__MODULE__{
          uco: non_neg_integer(),
          token: %{{binary(), non_neg_integer()} => non_neg_integer()},
          last_chain_sync_date: DateTime.t()
        }

  def serialize(%__MODULE__{
        uco: uco_balance,
        token: token_balances,
        last_chain_sync_date: last_chain_sync_date
      }) do
    token_balances_binary =
      token_balances
      |> Enum.reduce([], fn {{token_address, token_id}, amount}, acc ->
        [<<token_address::binary, amount::64, VarInt.from_value(token_id)::binary>> | acc]
      end)
      |> Enum.reverse()
      |> :erlang.list_to_binary()

    encoded_token_balances_length = map_size(token_balances) |> VarInt.from_value()

    <<uco_balance::64, encoded_token_balances_length::binary, token_balances_binary::binary,
      DateTime.to_unix(last_chain_sync_date, :millisecond)::64>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<uco_balance::64, rest::bitstring>>) do
    {nb_token_balances, rest} = rest |> VarInt.get_value()

    {token_balances, <<last_chain_sync_date::64, rest::bitstring>>} =
      deserialize_token_balances(rest, nb_token_balances, %{})

    {%__MODULE__{
       uco: uco_balance,
       token: token_balances,
       last_chain_sync_date: DateTime.from_unix!(last_chain_sync_date, :millisecond)
     }, rest}
  end

  defp deserialize_token_balances(rest, 0, _acc), do: {%{}, rest}

  defp deserialize_token_balances(rest, token_balances, acc)
       when map_size(acc) == token_balances do
    {acc, rest}
  end

  defp deserialize_token_balances(rest, nb_token_balances, acc) do
    {token_address, <<amount::64, rest::bitstring>>} = Utils.deserialize_address(rest)
    {token_id, rest} = VarInt.get_value(rest)

    deserialize_token_balances(
      rest,
      nb_token_balances,
      Map.put(acc, {token_address, token_id}, amount)
    )
  end
end
