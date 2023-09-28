defmodule Archethic.P2P.Message.SmartContractCallValidation do
  @moduledoc """
  Represents a module to attest the validation of a transaction towards a contract
  """

  @type t :: %__MODULE__{
          valid?: boolean(),
          fee: non_neg_integer()
        }

  defstruct [:valid?, :fee]

  @doc """
  Serialize message into binary

  ## Examples

      iex> %SmartContractCallValidation{valid?: true, fee: 186435476} |> SmartContractCallValidation.serialize()
      <<128, 0, 0, 0, 5, 142, 99, 202, 0::size(1)>>

      iex> %SmartContractCallValidation{valid?: false, fee: 186435476} |> SmartContractCallValidation.serialize()
      <<0, 0, 0, 0, 5, 142, 99, 202, 0::size(1)>>
  """
  def serialize(%__MODULE__{valid?: valid?, fee: fee}) do
    valid_bit = if valid?, do: 1, else: 0
    <<valid_bit::1, fee::64>>
  end

  @doc """
  Deserialize the encoded message

  ## Examples

      iex> SmartContractCallValidation.deserialize(<<128, 0, 0, 0, 5, 142, 99, 202, 0::size(1)>>)
      {
        %SmartContractCallValidation{valid?: true, fee: 186435476},
        ""
      }

      iex> SmartContractCallValidation.deserialize(<<0, 0, 0, 0, 5, 142, 99, 202, 0::size(1)>>)
      {
        %SmartContractCallValidation{valid?: false, fee: 186435476},
        ""
      }
  """
  def deserialize(<<valid_bit::1, fee::64, rest::bitstring>>) do
    valid? = if valid_bit == 1, do: true, else: false

    {%__MODULE__{valid?: valid?, fee: fee}, rest}
  end
end
