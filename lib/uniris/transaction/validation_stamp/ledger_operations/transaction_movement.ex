defmodule Uniris.Transaction.ValidationStamp.LedgerOperations.TransactionMovement do
  @moduledoc """
  Represents the ledger movements of the transaction extracted from
  the ledger or recipients part of the transaction and validated with the UTXO
  """
  @enforce_keys [:to, :amount]
  defstruct [:to, :amount]

  alias Uniris.Crypto

  @type t() :: %__MODULE__{
          to: binary(),
          amount: float()
        }

  @doc """
  Serialize a transaction movement into binary format

  ## Examples

        iex> Uniris.Transaction.ValidationStamp.LedgerOperations.TransactionMovement.serialize(
        ...>  %Uniris.Transaction.ValidationStamp.LedgerOperations.TransactionMovement{
        ...>    to: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
        ...>      159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        ...>    amount: 0.30
        ...>  }
        ...> )
        <<
        # Node public key
        0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
        159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
        # Amount
        63, 211, 51, 51, 51, 51, 51, 51
        >>
  """
  @spec serialize(__MODULE__.t()) :: <<_::64, _::_*8>>
  def serialize(%__MODULE__{to: to, amount: amount}) do
    <<to::binary, amount::float>>
  end

  @doc """
  Deserialize an encoded transaction movement

  ## Examples

    iex> <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
    ...> 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
    ...> 63, 211, 51, 51, 51, 51, 51, 51
    ...> >>
    ...> |> Uniris.Transaction.ValidationStamp.LedgerOperations.TransactionMovement.deserialize()
    {
      %Uniris.Transaction.ValidationStamp.LedgerOperations.TransactionMovement{
        to: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
          159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        amount: 0.30
      },
      ""
    }
  """
  @spec deserialize(bitstring()) :: {__MODULE__.t(), bitstring}
  def deserialize(<<hash_id::8, rest::bitstring>>) do
    hash_size = Crypto.hash_size(hash_id)
    <<address::binary-size(hash_size), amount::float, rest::bitstring>> = rest

    {
      %__MODULE__{
        to: <<hash_id::8>> <> address,
        amount: amount
      },
      rest
    }
  end
end
