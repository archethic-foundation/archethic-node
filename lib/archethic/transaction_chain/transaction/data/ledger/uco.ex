defmodule Archethic.TransactionChain.TransactionData.UCOLedger do
  @moduledoc """
  Represents a UCO ledger movement
  """
  defstruct transfers: []

  alias __MODULE__.Transfer

  alias Archethic.Utils.VarInt

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

      iex> %UCOLedger{
      ...>   transfers: [
      ...>     %Transfer{
      ...>       to:
      ...>         <<0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...>           165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>       amount: 1_050_000_000
      ...>     }
      ...>   ]
      ...> }
      ...> |> UCOLedger.serialize(1)
      <<1, 1, 0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52, 165,
        11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53, 0, 0, 0, 0, 62, 149, 186,
        128>>
  """
  @spec serialize(uco_ledger :: t(), tx_version :: pos_integer()) :: binary()
  def serialize(%__MODULE__{transfers: transfers}, tx_version) do
    transfers_bin =
      transfers
      |> Enum.map(&Transfer.serialize(&1, tx_version))
      |> :erlang.list_to_binary()

    encoded_transfer = VarInt.from_value(length(transfers))
    <<encoded_transfer::binary, transfers_bin::binary>>
  end

  @doc """
  Deserialize an encoded UCO ledger

  ## Examples

      iex> <<1, 1, 0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...>   165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53, 0, 0, 0, 0, 62,
      ...>   149, 186, 128>>
      ...> |> UCOLedger.deserialize(1)
      {
        %UCOLedger{
          transfers: [
            %Transfer{
              to:
                <<0, 0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
                  165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
              amount: 1_050_000_000
            }
          ]
        },
        ""
      }
  """
  @spec deserialize(data :: bitstring(), tx_version :: non_neg_integer()) :: {t(), bitstring}
  def deserialize(data, tx_version) do
    {nb_transfers, rest} = VarInt.get_value(data)
    {transfers, rest} = do_reduce_transfers(rest, nb_transfers, [], tx_version)

    {
      %__MODULE__{
        transfers: transfers
      },
      rest
    }
  end

  defp do_reduce_transfers(rest, 0, _, _), do: {[], rest}

  defp do_reduce_transfers(rest, nb_transfers, acc, _tx_version) when length(acc) == nb_transfers,
    do: {Enum.reverse(acc), rest}

  defp do_reduce_transfers(binary, nb_transfers, acc, tx_version) do
    {transfer, rest} = Transfer.deserialize(binary, tx_version)
    do_reduce_transfers(rest, nb_transfers, [transfer | acc], tx_version)
  end

  @spec cast(map()) :: t()
  def cast(uco_ledger = %{}) do
    %__MODULE__{
      transfers: Map.get(uco_ledger, :transfers, []) |> Enum.map(&Transfer.cast/1)
    }
  end

  @spec to_map(t() | nil) :: map()
  def to_map(nil), do: %{transfers: []}

  def to_map(%__MODULE__{transfers: transfers}) do
    %{
      transfers: Enum.map(transfers, &Transfer.to_map/1)
    }
  end

  @doc """
  Return the total of uco transferred

  ## Examples

      iex> %UCOLedger{
      ...>   transfers: [
      ...>     %Transfer{
      ...>       to:
      ...>         <<0, 59, 140, 2, 130, 52, 88, 206, 176, 29, 10, 173, 95, 179, 27, 166, 66, 52,
      ...>           165, 11, 146, 194, 246, 89, 73, 85, 202, 120, 242, 136, 136, 63, 53>>,
      ...>       amount: 1_050_000_000
      ...>     },
      ...>     %Transfer{
      ...>       to:
      ...>         <<0, 202, 39, 113, 5, 117, 133, 141, 107, 1, 202, 156, 250, 124, 22, 13, 183, 20,
      ...>           221, 181, 252, 153, 184, 2, 26, 115, 73, 148, 163, 119, 163, 86, 6>>,
      ...>       amount: 2_290_000_000
      ...>     }
      ...>   ]
      ...> }
      ...> |> UCOLedger.total_amount()
      3_340_000_000
  """
  @spec total_amount(t()) :: non_neg_integer()
  def total_amount(%__MODULE__{transfers: transfers}) do
    Enum.reduce(transfers, 0, &(&2 + &1.amount))
  end
end
