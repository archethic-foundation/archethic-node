defmodule ArchEthic.P2P.Message.GetTransactionChainLength do
  @moduledoc """
  Represents a message to request the size of the transaction chain (number of transactions)
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias ArchEthic.Crypto
  alias ArchEthic.P2P.Message.TransactionChainLength
  alias ArchEthic.TransactionChain
  alias ArchEthic.Utils

  use ArchEthic.P2P.Message, message_id: 18

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }

  def encode(%__MODULE__{address: address}) do
    address
  end

  def decode(message) when is_bitstring(message) do
    {address, rest} = Utils.deserialize_address(message)

    {
      %__MODULE__{
        address: address
      },
      rest
    }
  end

  def process(%__MODULE__{address: address}) do
    %TransactionChainLength{
      length: TransactionChain.size(address)
    }
  end
end
