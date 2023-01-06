defmodule Archethic.P2P.Message.LastTransactionAddress do
  @moduledoc """
  Represents a message with the last address key from a transaction chain
  """
  @enforce_keys [:address]
  defstruct [:address, :timestamp]

  alias Archethic.Crypto

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          timestamp: DateTime.t()
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{address: address, timestamp: timestamp}) do
    <<241::8, address::binary, DateTime.to_unix(timestamp, :millisecond)::64>>
  end
end
