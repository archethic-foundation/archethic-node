defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput do
  @moduledoc """
  Represent an unspent transaction output linked to a protocol version
  """

  defstruct [:protocol_version, :unspent_output]

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  @type t :: %__MODULE__{
          protocol_version: pos_integer(),
          unspent_output: UnspentOutput.t()
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        protocol_version: protocol_version,
        unspent_output: unspent_output = %UnspentOutput{}
      }) do
    <<protocol_version::32, UnspentOutput.serialize(unspent_output, protocol_version)::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<protocol_version::32, rest::bitstring>>) do
    {unspent_output, rest} = UnspentOutput.deserialize(rest, protocol_version)

    {
      %__MODULE__{
        protocol_version: protocol_version,
        unspent_output: unspent_output
      },
      rest
    }
  end
end
