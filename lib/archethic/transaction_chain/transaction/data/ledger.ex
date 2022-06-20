defmodule Archethic.TransactionChain.TransactionData.Ledger do
  @moduledoc """
  Represents transaction ledger movements
  """
  alias Archethic.TransactionChain.TransactionData.NFTLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger

  defstruct uco: %UCOLedger{}, nft: %NFTLedger{}

  @typedoc """
  Ledger movements are composed from:
  - UCO: movements of UCO
  """
  @type t :: %__MODULE__{
          uco: UCOLedger.t(),
          nft: NFTLedger.t()
        }

  @doc """
  Serialize the ledger into binary format

  ## Examples

      iex> %Ledger{
      ...>   uco: %UCOLedger{transfers: [
      ...>     %UCOLedger.Transfer{
      ...>       to: <<0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...>           165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>       amount: 1_050_000_000
      ...>     }
      ...>   ]},
      ...>   nft: %NFTLedger{
      ...>     transfers: [
      ...>       %NFTLedger.Transfer{
      ...>         nft: <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
      ...>               197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
      ...>         to: <<0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...>               165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>         amount: 1_050_000_000,
      ...>         nft_id: 0
      ...>       }
      ...>     ]
      ...>   }
      ...> }
      ...> |> Ledger.serialize()
      <<
        # Number of UCO transfers
        1,
        # UCO Transfer recipient
        0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
        165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53,
        # UCO Transfer amount
        0, 0, 0, 0, 62, 149, 186, 128,
        # Number of NFT transfer
        1,
        # NFT address from
        0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
        197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175,
        # NFT transfer recipient
        0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
        165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53,
        # NFT transfer amount
        0, 0, 0, 0, 62, 149, 186, 128,
        # NFT ID
        0
      >>
  """
  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{uco: uco_ledger, nft: nft_ledger}) do
    <<UCOLedger.serialize(uco_ledger)::binary, NFTLedger.serialize(nft_ledger)::binary>>
  end

  @doc """
  Deserialize encoded ledger

  ## Examples

      iex> <<1, 0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...> 165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53,
      ...> 0, 0, 0, 0, 62, 149, 186, 128, 1, 0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92,
      ...> 122, 206, 185, 71, 140, 74, 197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175,
      ...> 0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...> 165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53,
      ...> 0, 0, 0, 0, 62, 149, 186, 128, 0>>
      ...> |> Ledger.deserialize()
      {
        %Ledger{
          uco: %UCOLedger{
            transfers: [
              %UCOLedger.Transfer{
                to: <<0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
                      165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
                amount: 1_050_000_000
              }
            ]
          },
          nft: %NFTLedger{
            transfers: [
              %NFTLedger.Transfer{
                nft: <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
                      197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
                to: <<0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
                      165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
                amount: 1_050_000_000,
                 nft_id: 0
              }
            ]
          }
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(binary) when is_bitstring(binary) do
    {uco_ledger, rest} = UCOLedger.deserialize(binary)
    {nft_ledger, rest} = NFTLedger.deserialize(rest)

    {
      %__MODULE__{
        uco: uco_ledger,
        nft: nft_ledger
      },
      rest
    }
  end

  @spec from_map(map()) :: t()
  def from_map(ledger = %{}) do
    %__MODULE__{
      uco: Map.get(ledger, :uco, %UCOLedger{}) |> UCOLedger.from_map(),
      nft: Map.get(ledger, :nft, %NFTLedger{}) |> NFTLedger.from_map()
    }
  end

  @spec to_map(t() | nil) :: map()
  def to_map(nil) do
    %{
      uco: UCOLedger.to_map(nil),
      nft: NFTLedger.to_map(nil)
    }
  end

  def to_map(%__MODULE__{uco: uco, nft: nft}) do
    %{
      uco: UCOLedger.to_map(uco),
      nft: NFTLedger.to_map(nft)
    }
  end

  @doc """
  Returns the total amount of assets transferred

  ## Examples

      iex> %Ledger{
      ...>   uco: %UCOLedger{transfers: [
      ...>     %UCOLedger.Transfer{
      ...>       to: <<0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...>           165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>       amount: 1_050_000_000
      ...>     },
      ...>   ]},
      ...>   nft: %NFTLedger{
      ...>     transfers: [
      ...>       %NFTLedger.Transfer{
      ...>         nft: <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
      ...>               197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
      ...>         to: <<0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...>               165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>         amount: 1_050_000_000,
      ...>         nft_id: 0
      ...>       }
      ...>     ]
      ...>   }
      ...> }
      ...> |> Ledger.total_amount()
      2_100_000_000
  """
  @spec total_amount(t()) :: non_neg_integer()
  def total_amount(%__MODULE__{uco: uco_ledger, nft: nft_ledger}) do
    UCOLedger.total_amount(uco_ledger) + NFTLedger.total_amount(nft_ledger)
  end
end
