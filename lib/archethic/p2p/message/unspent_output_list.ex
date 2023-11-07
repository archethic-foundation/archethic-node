defmodule Archethic.P2P.Message.UnspentOutputList do
  @moduledoc """
  Represents a message with a list of unspent outputs
  """
  defstruct unspent_outputs: [], more?: false, offset: 0

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput
  alias Archethic.Utils.VarInt

  @type t :: %__MODULE__{
          unspent_outputs: list(VersionedUnspentOutput.t()),
          more?: boolean(),
          offset: non_neg_integer()
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{unspent_outputs: unspent_outputs, more?: more?, offset: offset}) do
    unspent_outputs_bin =
      unspent_outputs
      |> Stream.map(&VersionedUnspentOutput.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    encoded_unspent_outputs_length =
      unspent_outputs
      |> Enum.count()
      |> VarInt.from_value()

    more_bit = if more?, do: 1, else: 0

    <<encoded_unspent_outputs_length::binary, unspent_outputs_bin::bitstring, more_bit::1,
      VarInt.from_value(offset)::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {nb_unspent_outputs, rest} = rest |> VarInt.get_value()

    {unspent_outputs, <<more_bit::1, rest::bitstring>>} =
      deserialize_versioned_unspent_output_list(rest, nb_unspent_outputs, [])

    more? = more_bit == 1

    {offset, rest} = VarInt.get_value(rest)

    {%__MODULE__{unspent_outputs: unspent_outputs, more?: more?, offset: offset}, rest}
  end

  defp deserialize_versioned_unspent_output_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_versioned_unspent_output_list(rest, nb_unspent_outputs, acc)
       when length(acc) == nb_unspent_outputs do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_versioned_unspent_output_list(
         rest,
         nb_unspent_outputs,
         acc
       ) do
    {unspent_output, rest} = VersionedUnspentOutput.deserialize(rest)

    deserialize_versioned_unspent_output_list(rest, nb_unspent_outputs, [unspent_output | acc])
  end
end
