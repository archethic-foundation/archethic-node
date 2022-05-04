defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement.Type do
  @moduledoc """
  Represents a type of transaction movement.
  """

  alias Archethic.Crypto
  alias Archethic.Utils

  @typedoc """
  Transaction movement can be:
  - UCO transfers
  - NFT transfers. When it's a NFT transfer, the type indicates the address of NFT to transfer
  """
  @type t() :: :UCO | {:NFT, Crypto.versioned_hash()}

  def serialize(:UCO), do: <<0>>

  def serialize({:NFT, address}) do
    <<1::8, address::binary>>
  end

  def deserialize(<<0::8, rest::bitstring>>), do: {:UCO, rest}

  def deserialize(<<1::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {{:NFT, address}, rest}
  end
end
