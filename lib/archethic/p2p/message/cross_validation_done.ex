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

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          cross_validation_stamp: CrossValidationStamp.t()
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{address: address, cross_validation_stamp: stamp}) do
    <<10::8, address::binary, CrossValidationStamp.serialize(stamp)::bitstring>>
  end

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{address: tx_address, cross_validation_stamp: stamp}, _) do
    Mining.add_cross_validation_stamp(tx_address, stamp)
    %Ok{}
  end
end
