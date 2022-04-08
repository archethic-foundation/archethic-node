defmodule ArchEthic.P2P.Message.GetUnspentOutputs do
  @moduledoc """
  Represents a message to request the list of unspent outputs from a transaction
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias ArchEthic.Account
  alias ArchEthic.Crypto
  alias ArchEthic.P2P.Message.UnspentOutputList
  alias ArchEthic.Utils

  use ArchEthic.P2P.Message, message_id: 5

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

  def process(%__MODULE__{address: tx_address}) do
    %UnspentOutputList{
      unspent_outputs: Account.get_unspent_outputs(tx_address)
    }
  end
end
