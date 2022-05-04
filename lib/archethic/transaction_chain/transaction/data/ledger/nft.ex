defmodule Archethic.TransactionChain.TransactionData.NFTLedger do
  @moduledoc """
  Represents a NFT ledger movement
  """
  defstruct transfers: []

  alias __MODULE__.Transfer

  @typedoc """
  UCO movement is composed from:
  - Transfers: List of NFT transfers
  """
  @type t :: %__MODULE__{
          transfers: list(Transfer.t())
        }

  @doc """
  Serialize a NFT ledger into binary format

  ## Examples

      iex> %NFTLedger{transfers: [
      ...>   %Transfer{
      ...>     nft:  <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
      ...>        197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
      ...>     to: <<0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...>         165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>     amount: 1_050_000_000
      ...>   }
      ...> ]}
      ...> |> NFTLedger.serialize()
      <<
        # Number of NFT transfers
        1,
        # NFT address
        0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
        197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175,
        # NFT recipient
        0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
        165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53,
        # NFT amount
        0, 0, 0, 0, 62, 149, 186, 128
      >>
  """
  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{transfers: transfers}) do
    transfers_bin = Enum.map(transfers, &Transfer.serialize/1) |> :erlang.list_to_binary()
    <<length(transfers)::8, transfers_bin::binary>>
  end

  @doc """
  Deserialize an encoded NFT ledger

  ## Examples

      iex> <<1, 0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
      ...> 197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175, 0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...> 165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53,
      ...> 0, 0, 0, 0, 62, 149, 186, 128>>
      ...> |> NFTLedger.deserialize()
      {
        %NFTLedger{
          transfers: [
            %Transfer{
              nft: <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
                    197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
              to: <<0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
                    165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
              amount: 1_050_000_000
            }
          ]
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<0::8, rest::bitstring>>) do
    {
      %__MODULE__{},
      rest
    }
  end

  def deserialize(<<nb_transfers::8, rest::bitstring>>) do
    {transfers, rest} = do_reduce_transfers(rest, nb_transfers, [])

    {
      %__MODULE__{
        transfers: transfers
      },
      rest
    }
  end

  defp do_reduce_transfers(rest, nb_transfers, acc) when length(acc) == nb_transfers,
    do: {Enum.reverse(acc), rest}

  defp do_reduce_transfers(binary, nb_transfers, acc) do
    {transfer, rest} = Transfer.deserialize(binary)
    do_reduce_transfers(rest, nb_transfers, [transfer | acc])
  end

  @spec from_map(map()) :: t()
  def from_map(nft_ledger = %{}) do
    %__MODULE__{
      transfers: Map.get(nft_ledger, :transfers, []) |> Enum.map(&Transfer.from_map/1)
    }
  end

  @spec to_map(t() | nil) :: map()
  def to_map(nil), do: %{transfers: []}

  def to_map(nft_ledger = %__MODULE__{}) do
    %{
      transfers:
        nft_ledger
        |> Map.get(:transfers, [])
        |> Enum.map(&Transfer.to_map/1)
    }
  end

  @doc """
  Return the total of uco transferred

  ## Examples

      iex> %NFTLedger{transfers: [
      ...>   %Transfer{
      ...>     nft: <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
      ...>         197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
      ...>     to: <<0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...>         165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>     amount: 1_050_000_000
      ...>   },
      ...>   %Transfer{
      ...>     nft: <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
      ...>         197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
      ...>     to: <<0, 0, 202, 39, 113, 5, 117, 133, 141, 107, 1, 202, 156, 250, 124, 22, 13, 183, 20,
      ...>         221, 181, 252, 153, 184, 2, 26, 115, 73, 148, 163, 119, 163, 86, 6>>,
      ...>     amount: 2_290_000_000
      ...>   }
      ...> ]}
      ...> |> NFTLedger.total_amount()
      3_340_000_000
  """
  @spec total_amount(t()) :: non_neg_integer()
  def total_amount(%__MODULE__{transfers: transfers}) do
    Enum.reduce(transfers, 0, &(&2 + &1.amount))
  end
end
