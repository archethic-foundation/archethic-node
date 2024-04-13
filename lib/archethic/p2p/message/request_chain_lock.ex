defmodule Archethic.P2P.Message.RequestChainLock do
  @moduledoc """
  Request to a storage pool to lock the validation of a transaction in a chain
  """

  @enforce_keys [:address, :hash]
  defstruct [:address, :hash]

  alias Archethic.Crypto
  alias Archethic.Mining.ChainLock
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Error
  alias Archethic.Utils

  @type t :: %__MODULE__{address: Crypto.prepended_hash(), hash: Crypto.versioned_hash()}

  @spec process(__MODULE__.t(), Message.metadata()) :: Ok.t() | Error.t()
  def process(%__MODULE__{address: address, hash: hash}, _) do
    case ChainLock.lock(address, hash) do
      :ok -> %Ok{}
      {:error, :already_locked} -> %Error{reason: :already_locked}
    end
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address, hash: hash}) do
    <<address::binary, hash::binary-size(33)>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(bin) do
    {address, <<hash::binary-size(33), rest::bitstring>>} = Utils.deserialize_address(bin)

    {%__MODULE__{address: address, hash: hash}, rest}
  end
end
