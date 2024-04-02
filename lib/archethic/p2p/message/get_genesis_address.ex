defmodule Archethic.P2P.Message.GetGenesisAddress do
  @moduledoc """
  Represents a message to request the first address from a transaction chain
  """

  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Utils
  alias Archethic.TransactionChain
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.GenesisAddress

  @type t() :: %__MODULE__{
          address: binary()
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: GenesisAddress.t()
  def process(%__MODULE__{address: address}, _) do
    genesis_address = TransactionChain.get_genesis_address(address)

    # Genesis is not a transaction, so to get the timestamp for the conflict resolver
    # we return the timestamp of the 1st transaction
    timestamp =
      case TransactionChain.get_first_transaction_address(genesis_address) do
        {:ok, {_first_tx_address, first_tx_timestamp}} ->
          first_tx_timestamp

        {:error, :transaction_not_exists} ->
          DateTime.utc_now()
      end

    %GenesisAddress{address: genesis_address, timestamp: timestamp}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address}), do: <<address::binary>>

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%__MODULE__{address: address}, rest}
  end
end
