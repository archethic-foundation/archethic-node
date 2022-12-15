defmodule Archethic.P2P.Message.ValidateTransaction do
  @moduledoc false

  @enforce_keys [:transaction]
  defstruct [:transaction]

  alias Archethic.TransactionChain.Transaction

  @type t :: %__MODULE__{
          transaction: Transaction.t()
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{transaction: tx}) do
    Transaction.serialize(tx)
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(bin) when is_bitstring(bin) do
    {tx, rest} = Transaction.deserialize(bin)

    {
      %__MODULE__{transaction: tx},
      rest
    }
  end
end
