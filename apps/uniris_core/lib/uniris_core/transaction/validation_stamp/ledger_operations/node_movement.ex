defmodule UnirisCore.Transaction.ValidationStamp.LedgerOperations.NodeMovement do
  @moduledoc """
  Represents the movements regarding the nodes involved during the
  transaction validation. The node public keys are present as well as their rewards
  """
  @enforce_keys [:to, :amount]
  defstruct [:to, :amount]

  @type t() :: %__MODULE__{
          to: binary(),
          amount: float()
        }

  alias UnirisCore.Crypto

  @doc """
  Serialize a node movement into binary format

  ## Examples

        iex> UnirisCore.Transaction.ValidationStamp.LedgerOperations.NodeMovement.serialize(
        ...>  %UnirisCore.Transaction.ValidationStamp.LedgerOperations.NodeMovement{
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
  Deserialize an encoded node movement

  ## Examples

    iex> <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
    ...> 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
    ...> 63, 211, 51, 51, 51, 51, 51, 51
    ...> >>
    ...> |> UnirisCore.Transaction.ValidationStamp.LedgerOperations.NodeMovement.deserialize()
    {
      %UnirisCore.Transaction.ValidationStamp.LedgerOperations.NodeMovement{
        to: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
          159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        amount: 0.30
      },
      ""
    }
  """
  @spec deserialize(bitstring()) :: {__MODULE__.t(), bitstring}
  def deserialize(<<curve_id::8, rest::bitstring>>) do
    key_size = Crypto.key_size(curve_id)
    <<key::binary-size(key_size), amount::float, rest::bitstring>> = rest

    {
      %__MODULE__{
        to: <<curve_id::8>> <> key,
        amount: amount
      },
      rest
    }
  end
end
