defmodule Archethic.TransactionChain.VersionedTransactionInput do
  @moduledoc """
  Represent a transaction input linked to a protocol version
  """

  defstruct [:protocol_version, :input]

  alias Archethic.TransactionChain.TransactionInput

  @type t :: %__MODULE__{
          protocol_version: pos_integer(),
          input: TransactionInput.t()
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        protocol_version: protocol_version,
        input: input = %TransactionInput{}
      }) do
    <<protocol_version::32, TransactionInput.serialize(input, protocol_version)::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<protocol_version::32, rest::bitstring>>) do
    {input, rest} = TransactionInput.deserialize(rest, protocol_version)

    {
      %__MODULE__{
        protocol_version: protocol_version,
        input: input
      },
      rest
    }
  end
end
