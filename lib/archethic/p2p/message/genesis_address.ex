defmodule Archethic.P2P.Message.GenesisAddress do
  @moduledoc """
  Represents a message to first address from the transaction chain
  """
  @enforce_keys [:address]
  defstruct [:address]

  @type t :: %__MODULE__{
          address: binary()
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{address: address}) do
    <<235::8, address::binary>>
  end
end
