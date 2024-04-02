defmodule Archethic.P2P.Message.GetNextAddresses do
  @moduledoc """
  Inform a  shard to start repair.
  """
  @enforce_keys [:address]
  defstruct [:address, :limit]

  alias Archethic.Crypto
  alias Archethic.Utils
  alias Archethic.Utils.VarInt
  alias Archethic.TransactionChain
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.AddressList

  @type t :: %__MODULE__{address: Crypto.prepended_hash()}

  @spec process(__MODULE__.t(), Message.metadata()) :: AddressList.t()
  def process(%__MODULE__{address: address, limit: limit}, _) do
    %AddressList{addresses: TransactionChain.get_next_addresses(address, limit)}
  end

  @doc """
  Serialize GetNextAddresses Struct
  """
  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address, limit: limit}) do
    <<address::binary, VarInt.from_value(limit)::binary>>
  end

  @doc """
  Deserialize GetNextAddresses Struct
  """
  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(bin) do
    {address, rest} = Utils.deserialize_address(bin)
    {limit, rest} = VarInt.get_value(rest)

    {%__MODULE__{address: address, limit: limit}, rest}
  end
end
