defmodule Archethic.P2P.Message.GenesisAddress do
  @moduledoc """
  Represents a message to first address from the transaction chain
  """
  alias Archethic.Utils

  @enforce_keys [:address]
  defstruct [:address]

  @type t :: %__MODULE__{
          address: binary()
        }

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
