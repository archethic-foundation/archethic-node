defmodule Archethic.P2P.Message.SmartContractCallValidation do
  @moduledoc """
  Represents a module to attest the validation of a transaction towards a contract
  """

  @type t :: %__MODULE__{
          valid?: boolean()
        }

  defstruct [:valid?]

  @doc """
  Serialize message into binary

  ## Examples

      iex> %SmartContractCallValidation{valid?: true} |> SmartContractCallValidation.serialize()
      <<1::1>>

      iex> %SmartContractCallValidation{valid?: false} |> SmartContractCallValidation.serialize()
      <<0::1>>
  """
  def serialize(%__MODULE__{valid?: valid?}) do
    valid_bit = if valid?, do: 1, else: 0
    <<valid_bit::1>>
  end

  @doc """
  Deserialize the encoded message

  ## Examples

      iex> SmartContractCallValidation.deserialize(<<1::1>>)
      {
        %SmartContractCallValidation{valid?: true},
        ""
      }

      iex> SmartContractCallValidation.deserialize(<<0::1>>)
      {
        %SmartContractCallValidation{valid?: false},
        ""
      }
  """
  def deserialize(<<valid_bit::1, rest::bitstring>>) do
    valid? = if valid_bit == 1, do: true, else: false

    {
      %__MODULE__{
        valid?: valid?
      },
      rest
    }
  end
end
