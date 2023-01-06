defmodule Archethic.P2P.Message.GetGenesisAddress do
  @moduledoc """
  Represents a message to request the first address from a transaction chain
  """

  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto
  alias Archethic.TransactionChain
  alias Archethic.P2P.Message.FirstAddress

  @type t() :: %__MODULE__{
          address: binary()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: FirstAddress.t()
  def process(%__MODULE__{address: address}, _) do
    genesis_address = TransactionChain.get_genesis_address(address)
    %FirstAddress{address: genesis_address}
  end
end
