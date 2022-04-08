defmodule ArchEthic.P2P.Message.GetFirstPublicKey do
  @moduledoc """
  Represents a message to request the first public key from a transaction chain
  """

  @enforce_keys [:address]
  defstruct [:address]

  @type t() :: %__MODULE__{
          address: binary()
        }

  alias ArchEthic.P2P.Message.FirstPublicKey
  alias ArchEthic.P2P.Message.NotFound
  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction

  def process(%__MODULE__{address: address}) do
    case TransactionChain.get_first_transaction(address, [:previous_public_key]) do
      {:ok, %Transaction{previous_public_key: key}} ->
        %FirstPublicKey{public_key: key}

      {:error, :transaction_not_exists} ->
        %NotFound{}
    end
  end
end
