defmodule Archethic.P2P.Message.GetTransactionInputs do
  @moduledoc """
  Represents a message to request the inputs (spent or unspents) from a transaction
  """
  @enforce_keys [:address]
  defstruct [:address, offset: 0, limit: 0]

  alias Archethic.Crypto
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.TransactionInputList
  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          offset: non_neg_integer(),
          limit: non_neg_integer()
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: TransactionInputList.t()
  def process(%__MODULE__{address: address, offset: offset, limit: limit}, _) do
    {inputs, more?, offset} =
      address
      |> TransactionChain.get_inputs()
      |> Enum.sort_by(& &1.input.timestamp, {:desc, DateTime})
      |> Utils.limit_list(limit, offset, 3_000_000, fn input ->
        input |> VersionedTransactionInput.serialize() |> byte_size
      end)

    %TransactionInputList{
      inputs: inputs,
      more?: more?,
      offset: offset
    }
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address, offset: offset, limit: limit}) do
    <<address::binary, VarInt.from_value(offset)::binary, VarInt.from_value(limit)::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {offset, rest} = VarInt.get_value(rest)
    {limit, rest} = VarInt.get_value(rest)
    {%__MODULE__{address: address, offset: offset, limit: limit}, rest}
  end
end
