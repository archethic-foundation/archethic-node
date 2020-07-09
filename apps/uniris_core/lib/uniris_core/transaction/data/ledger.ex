defmodule UnirisCore.TransactionData.Ledger do
  @moduledoc """
  Represents transaction ledger movements
  """
  alias UnirisCore.TransactionData.UCOLedger

  defstruct uco: %UCOLedger{}

  @typedoc """
  Ledger movements are composed from:
  - UCO: movements of UCO
  """
  @type t :: %__MODULE__{
          uco: UCOLedger.t()
        }

  @doc """
  Serialize the ledger into binary format

  ## Examples

      iex> UnirisCore.TransactionData.Ledger.serialize(%UnirisCore.TransactionData.Ledger{
      ...>   uco: %UnirisCore.TransactionData.UCOLedger{transfers: [
      ...>     %UnirisCore.TransactionData.Ledger.Transfer{
      ...>       to: <<0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...>           165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>       amount: 10.5
      ...>     }
      ...>   ]}
      ...> })
      <<
        # Number of UCO transfers
        1,
        # UCO Transfer recipient
        0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
        165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53,
        # UCO Transfer amount
        64, 37, 0, 0, 0, 0, 0, 0
      >>
  """
  @spec serialize(__MODULE__.t()) :: binary()
  def serialize(%__MODULE__{uco: uco_ledger}) do
    <<UCOLedger.serialize(uco_ledger)::binary>>
  end

  @doc """
  Deserialize encoded ledger

  ## Examples

      iex> <<1, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...> 165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53,
      ...> 64, 37, 0, 0, 0, 0, 0, 0>>
      ...> |> UnirisCore.TransactionData.Ledger.deserialize()
      {
        %UnirisCore.TransactionData.Ledger{
          uco: %UnirisCore.TransactionData.UCOLedger{
            transfers: [
              %UnirisCore.TransactionData.Ledger.Transfer{
                to: <<0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
                      165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
                amount: 10.5
              }
            ]
          }
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {__MODULE__.t(), bitstring()}
  def deserialize(binary) when is_bitstring(binary) do
    {uco_ledger, rest} = UCOLedger.deserialize(binary)

    {
      %__MODULE__{
        uco: uco_ledger
      },
      rest
    }
  end
end
