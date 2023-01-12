defmodule Archethic.P2P.Message.TransactionInputList do
  @moduledoc """
  Represents a message with a list of transaction inputs
  """
  defstruct inputs: [], more?: false, offset: 0

  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.Utils.VarInt

  @type t() :: %__MODULE__{
          inputs: list(VersionedTransactionInput.t()),
          more?: boolean(),
          offset: non_neg_integer()
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{inputs: inputs, more?: more?, offset: offset}) do
    inputs_bin =
      inputs
      |> Stream.map(&VersionedTransactionInput.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    encoded_inputs_length = length(inputs) |> VarInt.from_value()

    more_bit = if more?, do: 1, else: 0

    <<encoded_inputs_length::binary, inputs_bin::bitstring, more_bit::1,
      VarInt.from_value(offset)::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {nb_inputs, rest} = rest |> VarInt.get_value()

    {inputs, <<more_bit::1, rest::bitstring>>} =
      deserialize_versioned_transaction_inputs(rest, nb_inputs, [])

    more? = more_bit == 1

    {offset, rest} = VarInt.get_value(rest)

    {%__MODULE__{
       inputs: inputs,
       more?: more?,
       offset: offset
     }, rest}
  end

  defp deserialize_versioned_transaction_inputs(rest, 0, _acc), do: {[], rest}

  defp deserialize_versioned_transaction_inputs(rest, nb_inputs, acc)
       when length(acc) == nb_inputs do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_versioned_transaction_inputs(
         rest,
         nb_inputs,
         acc
       ) do
    {input, rest} = VersionedTransactionInput.deserialize(rest)
    deserialize_versioned_transaction_inputs(rest, nb_inputs, [input | acc])
  end
end
