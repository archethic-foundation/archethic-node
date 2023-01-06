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

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{inputs: inputs, more?: more?, offset: offset}) do
    inputs_bin =
      inputs
      |> Stream.map(&VersionedTransactionInput.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    encoded_inputs_length = length(inputs) |> VarInt.from_value()

    more_bit = if more?, do: 1, else: 0

    <<244::8, encoded_inputs_length::binary, inputs_bin::bitstring, more_bit::1,
      VarInt.from_value(offset)::binary>>
  end
end
