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

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{unspent_outputs: unspent_outputs, more?: more?, offset: offset}) do
    unspent_outputs_bin =
      unspent_outputs
      |> Stream.map(&VersionedUnspentOutput.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_binary()

    encoded_unspent_outputs_length =
      unspent_outputs
      |> Enum.count()
      |> VarInt.from_value()

    more_bit = if more?, do: 1, else: 0

    <<250::8, encoded_unspent_outputs_length::binary, unspent_outputs_bin::binary, more_bit::1,
      VarInt.from_value(offset)::binary>>
  end
end
