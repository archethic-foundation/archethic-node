defmodule ArchEthic.P2P.Message.NewBeaconTransaction do
  @moduledoc """
  Represents a message for a new beacon slot transaction
  """

  @enforce_keys [:transaction]
  defstruct [:transaction]

  alias ArchEthic.BeaconChain
  alias ArchEthic.P2P.Message.Error
  alias ArchEthic.P2P.Message.Ok
  alias ArchEthic.TransactionChain.Transaction

  use ArchEthic.P2P.Message, message_id: 27

  @type t :: %__MODULE__{
          transaction: Transaction.t()
        }

  def encode(%__MODULE__{transaction: tx}) do
    Transaction.serialize(tx)
  end

  def decode(message) when is_bitstring(message) do
    Transaction.deserialize(message)
  end

  def process(%__MODULE__{transaction: tx}) do
    case BeaconChain.load_transaction(tx) do
      :ok ->
        %Ok{}

      :error ->
        %Error{reason: :invalid_transaction}
    end
  end
end
