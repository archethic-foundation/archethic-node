defmodule Archethic.P2P.Message.GetBalance do
  @moduledoc """
  Represents a message to request the balance of a transaction
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto
  alias Archethic.Account
  alias Archethic.P2P.Message.Balance

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{address: address}) do
    <<16::8, address::binary>>
  end

  @spec process(__MODULE__.t(), Crypto.key()) :: Balance.t()
  def process(%__MODULE__{address: address}, _) do
    %{uco: uco, token: token} = Account.get_balance(address)

    %Balance{
      uco: uco,
      token: token
    }
  end
end
