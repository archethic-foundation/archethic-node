defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement.Type do
  @moduledoc """
  Represents a type of transaction movement.
  """

  alias Archethic.Crypto
  alias Archethic.Utils

  @typedoc """
  Transaction movement can be:
  - UCO transfers
  - NFT transfers. When it's a NFT transfer, the type indicates the address of NFT to transfer, followed by nft_id
  """
  @type t() :: :UCO | {:NFT, Crypto.versioned_hash(), non_neg_integer()}

  def serialize(:UCO), do: <<0>>

  def serialize({:NFT, address, nft_id}) do
    <<1::8, address::binary, nft_id::8>>
  end

  def deserialize(<<0::8, rest::bitstring>>), do: {:UCO, rest}

  def deserialize(<<1::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    <<nft_id::8, rest::bitstring>> = rest
    {{:NFT, address, nft_id}, rest}
  end
end
