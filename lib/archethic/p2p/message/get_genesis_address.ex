defmodule Archethic.P2P.Message.GetGenesisAddress do
  @moduledoc """
  Represents a message to request the first address from a transaction chain
  """

  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto
  alias Archethic.Utils
  alias Archethic.TransactionChain
  alias Archethic.P2P.Message.GenesisAddress

  @type t() :: %__MODULE__{
          address: binary()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: GenesisAddress.t()
  def process(%__MODULE__{address: address}, _) do
    genesis_address = TransactionChain.get_genesis_address(address)
    %GenesisAddress{address: genesis_address}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address}), do: <<address::binary>>

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%__MODULE__{address: address}, rest}
  end
end
