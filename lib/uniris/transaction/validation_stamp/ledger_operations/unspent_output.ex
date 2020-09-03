defmodule Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput do
  @moduledoc """
  Represents an unspent output from a transaction.
  """
  @enforce_keys [:amount, :from]
  defstruct [:amount, :from]

  @type t :: %__MODULE__{
          amount: float(),
          from: binary()
        }

  alias Uniris.Crypto

  @doc """
  Serialize unspent output into binary format

  ## Examples

        iex> Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput.serialize(
        ...>  %Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput{
        ...>    from: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
        ...>      159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        ...>    amount: 10.5
        ...>  }
        ...> )
        <<
        # From
        0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
        159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
        # Amount
        64, 37, 0, 0, 0, 0, 0, 0
        >>
  """
  @spec serialize(__MODULE__.t()) :: <<_::64, _::_*8>>
  def serialize(%__MODULE__{from: from, amount: amount}) do
    <<from::binary, amount::float>>
  end

  @doc """
  Deserialize an encoded unspent output

  ## Examples

    iex> <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
    ...> 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
    ...> 64, 37, 0, 0, 0, 0, 0, 0
    ...> >>
    ...> |> Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput.deserialize()
    {
      %Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput{
        from: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
          159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        amount: 10.5
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
        from: <<hash_id::8>> <> address,
        amount: amount
      },
      rest
    }
  end

  @spec from_map(map()) :: __MODULE__.t()
  def from_map(utxo = %{}) do
    %__MODULE__{
      from: Map.get(utxo, :from),
      amount: Map.get(utxo, :amount)
    }
  end

  @spec to_map(__MODULE__.t()) :: map()
  def to_map(%__MODULE__{from: from, amount: amount}) do
    %{
      from: from,
      amount: amount
    }
  end
end
