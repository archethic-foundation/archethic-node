defmodule Archethic.P2P.Message.GetTransactionChainLength do
  @moduledoc """
  Represents a message to request the size of the transaction chain (number of transactions)
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto
  alias Archethic.TransactionChain
  alias Archethic.P2P.Message.TransactionChainLength

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{address: address}) do
    <<18::8, address::binary>>
  end

  # Returns the length of the transaction chain
  @spec process(__MODULE__.t(), Crypto.key()) :: TransactionChainLength.t()
  def process(%__MODULE__{address: address}, _) do
    %TransactionChainLength{
      length: TransactionChain.size(address)
    }
  end
end
