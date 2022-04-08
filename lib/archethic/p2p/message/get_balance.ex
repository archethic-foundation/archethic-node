defmodule ArchEthic.P2P.Message.GetBalance do
  @moduledoc """
  Represents a message to request the balance of a transaction
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias ArchEthic.Account
  alias ArchEthic.Crypto
  alias ArchEthic.P2P.Message.Balance
  alias ArchEthic.Utils

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }
  use ArchEthic.P2P.Message, message_id: 16

  def encode(%__MODULE__{address: address}) do
    address
  end

  def decode(message) do
    {address, rest} = Utils.deserialize_address(message)

    {%__MODULE__{
       address: address
     }, rest}
  end

  def process(%__MODULE__{address: address}) do
    %{uco: uco, nft: nft} = Account.get_balance(address)

    %Balance{
      uco: uco,
      nft: nft
    }
  end
end
