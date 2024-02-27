defmodule Archethic.P2P.Message.GetBalance do
  @moduledoc """
  Represents a message to request the balance of a transaction
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto
  alias Archethic.Utils
  alias Archethic.UTXO
  alias Archethic.P2P.Message.Balance

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Balance.t()
  def process(%__MODULE__{address: address}, _) do
    %{uco: uco, token: token} = UTXO.get_balance(address)

    %Balance{
      uco: uco,
      token: token
    }
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address}) do
    <<address::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%__MODULE__{address: address}, rest}
  end
end
