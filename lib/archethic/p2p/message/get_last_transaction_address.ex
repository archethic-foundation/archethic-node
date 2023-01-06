defmodule Archethic.P2P.Message.GetLastTransactionAddress do
  @moduledoc """
  Represents a message to request the last transaction address of a chain
  """
  @enforce_keys [:address, :timestamp]
  defstruct [:address, :timestamp]

  alias Archethic.Crypto
  alias Archethic.TransactionChain
  alias Archethic.P2P.Message.LastTransactionAddress

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          timestamp: DateTime.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: LastTransactionAddress.t()
  def process(%__MODULE__{address: address, timestamp: timestamp}, _) do
    {address, time} = TransactionChain.get_last_address(address, timestamp)
    %LastTransactionAddress{address: address, timestamp: time}
  end
end
