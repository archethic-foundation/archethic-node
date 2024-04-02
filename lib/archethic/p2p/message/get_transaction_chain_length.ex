defmodule Archethic.P2P.Message.GetTransactionChainLength do
  @moduledoc """
  Represents a message to request the size of the transaction chain (number of transactions)
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto
  alias Archethic.TransactionChain
  alias Archethic.Utils
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.TransactionChainLength

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }

  # Returns the length of the transaction chain
  @spec process(__MODULE__.t(), Message.metadata()) :: TransactionChainLength.t()
  def process(%__MODULE__{address: address}, _) do
    %TransactionChainLength{
      length: TransactionChain.get_size(address)
    }
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address}) do
    <<address::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%__MODULE__{address: address}, rest}
  end
end
