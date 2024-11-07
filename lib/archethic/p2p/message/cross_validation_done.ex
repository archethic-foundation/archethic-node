defmodule Archethic.P2P.Message.CrossValidationDone do
  @moduledoc """
  Represents a message to notify the end of the cross validation for a given transaction address

  This message is used during the mining process by the cross validation nodes.
  """
  @enforce_keys [:address, :cross_validation_stamp]
  defstruct [:address, :cross_validation_stamp]

  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.Mining
  alias Archethic.P2P.Message.Ok
  alias Archethic.Utils

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          cross_validation_stamp: CrossValidationStamp.t()
        }

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {stamp, rest} = CrossValidationStamp.deserialize(rest)

    {%__MODULE__{
       address: address,
       cross_validation_stamp: stamp
     }, rest}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address, cross_validation_stamp: stamp}) do
    <<address::binary, CrossValidationStamp.serialize(stamp)::bitstring>>
  end

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{address: tx_address, cross_validation_stamp: stamp}, from) do
    Mining.add_cross_validation_stamp(tx_address, stamp, from)
    %Ok{}
  end
end
