defmodule Uniris.TransactionData.UCOLedger do
  @moduledoc """
  Represents a UCO ledger movement
  """
  defstruct [:fee, transfers: []]

  alias Uniris.TransactionData.Ledger.Transfer

  @typedoc """
  UCO movement is composed from:
  - Fee: End user can specify the fee to use (nodes will check if it's sufficient)
  - Transfers: List of UCO transfers
  """
  @type t :: %__MODULE__{
          fee: float(),
          transfers: list(Transfer.t())
        }

  @doc """
  Serialize uco ledger into binary format

  ## Examples

      iex> Uniris.TransactionData.UCOLedger.serialize(%Uniris.TransactionData.UCOLedger{transfers: [
      ...>   %Uniris.TransactionData.Ledger.Transfer{
      ...>     to: <<0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...>         165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>     amount: 10.5
      ...>   }
      ...> ]})
      <<
        # Number of transfers
        1,
        # Transfer recipient
        0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
        165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53,
        # Transfer amount
        64, 37, 0, 0, 0, 0, 0, 0
      >>
  """
  @spec serialize(Uniris.TransactionData.UCOLedger.t()) :: binary()
  def serialize(%__MODULE__{transfers: transfers}) do
    transfers_bin = Enum.map(transfers, &Transfer.serialize/1) |> :erlang.list_to_binary()
    <<length(transfers)::8, transfers_bin::binary>>
  end

  @doc """
  Deserialize an encoded uco ledger

  ## Examples

      iex> <<1, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...> 165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53, 64, 37, 0, 0, 0, 0, 0, 0>>
      ...> |> Uniris.TransactionData.UCOLedger.deserialize()
      {
        %Uniris.TransactionData.UCOLedger{
          transfers: [
            %Uniris.TransactionData.Ledger.Transfer{
              to: <<0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
                    165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
              amount: 10.5
            }
          ]
        },
        ""
      }

      iex> Uniris.TransactionData.UCOLedger.deserialize(<<0, 156, 213, 216, 36, 138, 118, 198, 118, 250, 70, 24, 14, 67, 139, 145, 229,
      ...> 210, 59, 183, 114, 172, 168, 216, 88, 80, 55, 26, 25, 160, 146, 13, 131>>)
      {
        %Uniris.TransactionData.UCOLedger{
          transfers: []
        },
        <<156, 213, 216, 36, 138, 118, 198, 118, 250, 70, 24, 14, 67, 139, 145, 229,
        210, 59, 183, 114, 172, 168, 216, 88, 80, 55, 26, 25, 160, 146, 13, 131>>
      }

  """
  @spec deserialize(bitstring()) :: {__MODULE__.t(), bitstring}
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

  @spec from_map(map()) :: __MODULE__.t()
  def from_map(uco_ledger = %{}) do
    %__MODULE__{
      fee: Map.get(uco_ledger, :fee),
      transfers: Map.get(uco_ledger, :transfers, []) |> Enum.map(&Transfer.from_map/1)
    }
  end

  @spec to_map(__MODULE__.t()) :: map()
  def to_map(%__MODULE__{fee: fee, transfers: transfers}) do
    %{
      fee: fee,
      transfers: Enum.map(transfers, &Transfer.to_map/1)
    }
  end
end
