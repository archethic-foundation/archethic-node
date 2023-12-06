defmodule Archethic.P2P.Message.SmartContractCallValidation do
  @moduledoc """
  Represents a module to attest the validation of a transaction towards a contract
  """

  alias Archethic.Utils.VarInt

  @type t :: %__MODULE__{
          valid?: boolean(),
          reason: nil | String.t(),
          fee: non_neg_integer()
        }

  defstruct [:valid?, :fee, :reason]

  @doc """
  Serialize message into binary
  """
  def serialize(%__MODULE__{valid?: valid?, fee: fee, reason: reason}) do
    valid_bit = if valid?, do: 1, else: 0

    reason_length =
      case reason do
        nil -> 0
        _ -> byte_size(reason)
      end

    reason_length_serialized = VarInt.from_value(reason_length)

    reason_serialized =
      case reason do
        nil -> <<>>
        _ -> reason
      end

    <<valid_bit::1, fee::64, reason_length_serialized::binary, reason_serialized::binary>>
  end

  @doc """
  Deserialize the encoded message
  """
  def deserialize(<<valid_bit::1, fee::64, rest::bitstring>>) do
    valid? = if valid_bit == 1, do: true, else: false

    {reason_length, rest} = VarInt.get_value(rest)

    {reason, rest} =
      case reason_length do
        0 ->
          {nil, rest}

        _ ->
          <<reason::binary-size(reason_length), rest::bitstring>> = rest
          {reason, rest}
      end

    {%__MODULE__{valid?: valid?, fee: fee, reason: reason}, rest}
  end
end
