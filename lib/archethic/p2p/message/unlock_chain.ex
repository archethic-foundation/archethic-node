defmodule Archethic.P2P.Message.UnlockChain do
  @moduledoc """
  Request a storage node to unlock the chain for an address
  """
  alias Archethic.Crypto
  alias Archethic.Mining.ChainLock
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Ok
  alias Archethic.Utils

  @enforce_keys [:address]
  defstruct [:address]

  @type t :: %__MODULE__{address: Crypto.prepended_hash()}

  @spec process(__MODULE__.t(), Message.metadata()) :: Ok.t()
  def process(%__MODULE__{address: address}, _) do
    ChainLock.unlock(address)
    %Ok{}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address}), do: <<address::binary>>

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(bin) do
    {address, rest} = Utils.deserialize_address(bin)
    {%__MODULE__{address: address}, rest}
  end
end
