defmodule ArchEthic.P2P.Message.Balance do
  @moduledoc """
  Represents a message with the balance of a transaction
  """
  defstruct uco: 0, nft: %{}

  @type t :: %__MODULE__{
          uco: non_neg_integer(),
          nft: %{binary() => non_neg_integer()}
        }

  use ArchEthic.P2P.Message, message_id: 248

  alias ArchEthic.Utils

  def encode(%__MODULE__{uco: uco_balance, nft: nft_balances}) do
    nft_balances_binary =
      nft_balances
      |> Enum.reduce([], fn {nft_address, amount}, acc ->
        [<<nft_address::binary, amount::float>> | acc]
      end)
      |> Enum.reverse()
      |> :erlang.list_to_binary()

    <<uco_balance::float, map_size(nft_balances)::16, nft_balances_binary::binary>>
  end

  def decode(<<uco_balance::float, nb_nft_balances::16, rest::bitstring>>) do
    {nft_balances, rest} = deserialize_nft_balances(rest, nb_nft_balances, %{})

    {%__MODULE__{
       uco: uco_balance,
       nft: nft_balances
     }, rest}
  end

  defp deserialize_nft_balances(rest, 0, _acc), do: {%{}, rest}

  defp deserialize_nft_balances(rest, nft_balances, acc) when map_size(acc) == nft_balances do
    {acc, rest}
  end

  defp deserialize_nft_balances(rest, nb_nft_balances, acc) do
    {nft_address, <<amount::float, rest::bitstring>>} = Utils.deserialize_address(rest)
    deserialize_nft_balances(rest, nb_nft_balances, Map.put(acc, nft_address, amount))
  end

  def process(%__MODULE__{}) do
  end
end
