defmodule ArchEthic.P2P.Message.CrossValidationDone do
  @moduledoc """
  Represents a message to notify the end of the cross validation for a given transaction address

  This message is used during the mining process by the cross validation nodes.
  """
  @enforce_keys [:address, :cross_validation_stamp]
  defstruct [:address, :cross_validation_stamp]

  alias ArchEthic.Crypto
  alias ArchEthic.Mining
  alias ArchEthic.P2P.Message.Ok
  alias ArchEthic.TransactionChain.Transaction.CrossValidationStamp
  alias ArchEthic.Utils

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          cross_validation_stamp: CrossValidationStamp.t()
        }

  use ArchEthic.P2P.Message, message_id: 10

  def encode(%__MODULE__{address: address, cross_validation_stamp: stamp}) do
    <<address::binary, CrossValidationStamp.serialize(stamp)::bitstring>>
  end

  def decode(message) do
    {address, rest} = Utils.deserialize_address(message)
    {stamp, rest} = CrossValidationStamp.deserialize(rest)

    {%__MODULE__{
       address: address,
       cross_validation_stamp: stamp
     }, rest}
  end

  def process(%__MODULE__{address: tx_address, cross_validation_stamp: stamp}) do
    Mining.add_cross_validation_stamp(tx_address, stamp)
    %Ok{}
  end
end
