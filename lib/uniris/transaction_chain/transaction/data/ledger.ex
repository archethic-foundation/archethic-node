defmodule Uniris.TransactionChain.TransactionData.Ledger do
  @moduledoc """
  Represents transaction ledger movements
  """
  alias Uniris.TransactionChain.TransactionData.UCOLedger

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

      iex> %Ledger{
      ...>   uco: %UCOLedger{transfers: [
      ...>     %Transfer{
      ...>       to: <<0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...>           165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>       amount: 10.5
      ...>     }
      ...>   ]}
      ...> }
      ...> |> Ledger.serialize()
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
      ...> |> Ledger.deserialize()
      {
        %Ledger{
          uco: %UCOLedger{
            transfers: [
              %Transfer{
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

  @spec from_map(map()) :: __MODULE__.t()
  def from_map(ledger = %{}) do
    %__MODULE__{
      uco: Map.get(ledger, :uco, %UCOLedger{}) |> UCOLedger.from_map()
    }
  end

  @spec to_map(__MODULE__.t()) :: map()
  def to_map(%__MODULE__{uco: uco}) do
    %{
      uco: UCOLedger.to_map(uco)
    }
  end

  @doc """
  Returns the total amount of assets transferred

  ## Examples

      iex> %Ledger{
      ...>   uco: %UCOLedger{transfers: [
      ...>     %Transfer{
      ...>       to: <<0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...>           165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>       amount: 10.5
      ...>     }
      ...>   ]}
      ...> }
      ...> |> Ledger.total_amount()
      10.5
  """
  @spec total_amount(__MODULE__.t()) :: float()
  def total_amount(%__MODULE__{uco: uco_ledger}) do
    UCOLedger.total_amount(uco_ledger)
  end
end
