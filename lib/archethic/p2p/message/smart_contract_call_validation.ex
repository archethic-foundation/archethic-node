defmodule Archethic.P2P.Message.SmartContractCallValidation do
  @moduledoc """
  Represents a module to attest the validation of a transaction towards a contract
  """

  @type t :: %__MODULE__{
          valid?: boolean()
        }

  defstruct [:valid?, :signature, :node_index]

  def serialize(%__MODULE__{valid?: valid?}) do
    valid_bit = if valid?, do: 1, else: 0
    <<valid_bit::1>>
  end

  def deserialize(<<valid_bit::8, rest::bitstring>>) do
    valid? = if valid_bit == 1, do: true, else: false

    {
      %__MODULE__{
        valid?: valid?
      },
      rest
    }
  end
end
