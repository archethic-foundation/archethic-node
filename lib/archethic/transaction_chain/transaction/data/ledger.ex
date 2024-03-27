defmodule Archethic.TransactionChain.TransactionData.Ledger do
  @moduledoc """
  Represents transaction ledger movements
  """
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger

  defstruct uco: %UCOLedger{}, token: %TokenLedger{}

  @typedoc """
  Ledger movements are composed from:
  - UCO: movements of UCO
  """
  @type t :: %__MODULE__{
          uco: UCOLedger.t(),
          token: TokenLedger.t()
        }

  @doc """
  Serialize the ledger into binary format

  ## Examples

      iex> %Ledger{
      ...>   uco: %UCOLedger{
      ...>     transfers: [
      ...>       %UCOLedger.Transfer{
      ...>         to:
      ...>           <<0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66,
      ...>             52, 165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>         amount: 1_050_000_000
      ...>       }
      ...>     ]
      ...>   },
      ...>   token: %TokenLedger{
      ...>     transfers: [
      ...>       %TokenLedger.Transfer{
      ...>         token_address:
      ...>           <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71,
      ...>             140, 74, 197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
      ...>         to:
      ...>           <<0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66,
      ...>             52, 165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>         amount: 1_050_000_000,
      ...>         token_id: 0
      ...>       }
      ...>     ]
      ...>   }
      ...> }
      ...> |> Ledger.serialize(current_transaction_version())
      <<
        # Number of UCO transfers
        1,
        1,
        # UCO Transfer recipient
        0,
        0,
        59,
        140,
        2,
        130,
        52,
        88,
        206,
        176,
        29,
        10,
        173,
        95,
        179,
        27,
        166,
        66,
        52,
        165,
        11,
        146,
        194,
        246,
        89,
        73,
        85,
        202,
        120,
        242,
        136,
        136,
        63,
        53,
        # UCO Transfer amount
        0,
        0,
        0,
        0,
        62,
        149,
        186,
        128,
        # Number of TOKEN transfer
        1,
        1,
        # TOKEN address from
        0,
        0,
        49,
        101,
        72,
        154,
        152,
        3,
        174,
        47,
        2,
        35,
        7,
        92,
        122,
        206,
        185,
        71,
        140,
        74,
        197,
        46,
        99,
        117,
        89,
        96,
        100,
        20,
        0,
        34,
        181,
        215,
        143,
        175,
        # TOKEN transfer recipient
        0,
        0,
        59,
        140,
        2,
        130,
        52,
        88,
        206,
        176,
        29,
        10,
        173,
        95,
        179,
        27,
        166,
        66,
        52,
        165,
        11,
        146,
        194,
        246,
        89,
        73,
        85,
        202,
        120,
        242,
        136,
        136,
        63,
        53,
        # TOKEN transfer amount
        0,
        0,
        0,
        0,
        62,
        149,
        186,
        128,
        # TOKEN ID
        1,
        0
      >>
  """
  @spec serialize(transaction_ledger :: t(), transaction_version :: pos_integer()) :: binary()
  def serialize(%__MODULE__{uco: uco_ledger, token: token_ledger}, tx_version) do
    <<UCOLedger.serialize(uco_ledger, tx_version)::binary,
      TokenLedger.serialize(token_ledger, tx_version)::binary>>
  end

  @doc """
  Deserialize encoded ledger

  ## Examples

      iex> <<1, 1, 0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...>   165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53, 0, 0, 0, 0, 62,
      ...>   149, 186, 128, 1, 1, 0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206,
      ...>   185, 71, 140, 74, 197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175, 0, 0,
      ...>   59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52, 165, 11, 146,
      ...>   194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53, 0, 0, 0, 0, 62, 149, 186, 128,
      ...>   1, 0>>
      ...> |> Ledger.deserialize(1)
      {
        %Ledger{
          uco: %UCOLedger{
            transfers: [
              %UCOLedger.Transfer{
                to:
                  <<0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
                    165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
                amount: 1_050_000_000
              }
            ]
          },
          token: %TokenLedger{
            transfers: [
              %TokenLedger.Transfer{
                token_address:
                  <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140,
                    74, 197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
                to:
                  <<0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
                    165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
                amount: 1_050_000_000,
                token_id: 0
              }
            ]
          }
        },
        ""
      }
  """
  @spec deserialize(data :: bitstring(), transaction_version :: pos_integer()) ::
          {t(), bitstring()}
  def deserialize(data, tx_version) when is_bitstring(data) do
    {uco_ledger, rest} = UCOLedger.deserialize(data, tx_version)
    {token_ledger, rest} = TokenLedger.deserialize(rest, tx_version)

    {
      %__MODULE__{
        uco: uco_ledger,
        token: token_ledger
      },
      rest
    }
  end

  @spec cast(map()) :: t()
  def cast(ledger = %{}) do
    %__MODULE__{
      uco: Map.get(ledger, :uco, %UCOLedger{}) |> UCOLedger.cast(),
      token: Map.get(ledger, :token, %TokenLedger{}) |> TokenLedger.cast()
    }
  end

  @spec to_map(t() | nil) :: map()
  def to_map(nil) do
    %{
      uco: UCOLedger.to_map(nil),
      token: TokenLedger.to_map(nil)
    }
  end

  def to_map(%__MODULE__{uco: uco, token: token}) do
    %{
      uco: UCOLedger.to_map(uco),
      token: TokenLedger.to_map(token)
    }
  end

  @doc """
  Returns the total amount of assets transferred

  ## Examples

      iex> %Ledger{
      ...>   uco: %UCOLedger{
      ...>     transfers: [
      ...>       %UCOLedger.Transfer{
      ...>         to:
      ...>           <<0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66,
      ...>             52, 165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>         amount: 1_050_000_000
      ...>       }
      ...>     ]
      ...>   },
      ...>   token: %TokenLedger{
      ...>     transfers: [
      ...>       %TokenLedger.Transfer{
      ...>         token_address:
      ...>           <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71,
      ...>             140, 74, 197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
      ...>         to:
      ...>           <<0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66,
      ...>             52, 165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>         amount: 1_050_000_000,
      ...>         token_id: 0
      ...>       }
      ...>     ]
      ...>   }
      ...> }
      ...> |> Ledger.total_amount()
      2_100_000_000
  """
  @spec total_amount(t()) :: non_neg_integer()
  def total_amount(%__MODULE__{uco: uco_ledger, token: token_ledger}) do
    UCOLedger.total_amount(uco_ledger) + TokenLedger.total_amount(token_ledger)
  end
end
