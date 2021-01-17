defmodule Uniris.TransactionChain.TransactionData.UCOLedger do
  @moduledoc """
  Represents a UCO ledger movement
  """
  defstruct transfers: []

  alias __MODULE__.Transfer

  @typedoc """
  UCO movement is composed from:
  - Transfers: List of UCO transfers
  """
  @type t :: %__MODULE__{
          transfers: list(Transfer.t())
        }

  @doc """
  Serialize a UCO ledger into binary format

  ## Examples

      iex> %UCOLedger{transfers: [
      ...>   %Transfer{
      ...>     to: <<0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...>         165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>     amount: 10.5
      ...>   }
      ...> ]}
      ...> |> UCOLedger.serialize()
      <<
        # Number of UCO transfers
        1,
        # UCO recipient
        0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
        165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53,
        # UCO amount
        64, 37, 0, 0, 0, 0, 0, 0
      >>
  """
  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{transfers: transfers}) do
    transfers_bin = Enum.map(transfers, &Transfer.serialize/1) |> :erlang.list_to_binary()
    <<length(transfers)::8, transfers_bin::binary>>
  end

  @doc """
  Deserialize an encoded UCO ledger

  ## Examples

      iex> <<1, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...> 165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53, 64, 37, 0, 0, 0, 0, 0, 0>>
      ...> |> UCOLedger.deserialize()
      {
        %UCOLedger{
          transfers: [
            %Transfer{
              to: <<0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
                    165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
              amount: 10.5
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
  def from_map(uco_ledger = %{}) do
    %__MODULE__{
      transfers: Map.get(uco_ledger, :transfers, []) |> Enum.map(&Transfer.from_map/1)
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{transfers: transfers}) do
    %{
      transfers: Enum.map(transfers, &Transfer.to_map/1)
    }
  end

  @doc """
  Return the total of uco transferred

  ## Examples

      iex> %UCOLedger{transfers: [
      ...>   %Transfer{
      ...>     to: <<0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...>         165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>     amount: 10.5
      ...>   },
      ...>   %Transfer{
      ...>     to: <<0, 202, 39, 113, 5, 117, 133, 141, 107, 1, 202, 156, 250, 124, 22, 13, 183, 20,
      ...>         221, 181, 252, 153, 184, 2, 26, 115, 73, 148, 163, 119, 163, 86, 6>>,
      ...>     amount: 22.9
      ...>   }
      ...> ]}
      ...> |> UCOLedger.total_amount()
      33.4
  """
  @spec total_amount(t()) :: float()
  def total_amount(%__MODULE__{transfers: transfers}) do
    Enum.reduce(transfers, 0.0, &(&2 + &1.amount))
  end
end
