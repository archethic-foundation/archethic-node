defmodule Archethic.P2P.Message.SmartContractCallValidation do
  @moduledoc """
  Response of ValidateSmartContractCall message.
  """

  alias Archethic.Contracts.Contract.Failure
  alias Archethic.Utils.VarInt

  @typedoc """
  `last_chain_sync_date` is used for conflict resolution. If there are no transaction yet, use epoch.
  """
  @type t :: %__MODULE__{
          status:
            :ok
            | {:error, :timeout}
            | {:error, :transaction_not_exists}
            | {:error, :insufficient_funds}
            | {:error, :invalid_execution, Failure.t()}
            | {:error, :invalid_condition, String.t()}
            | {:error, :parsing_error, String.t()},
          fee: non_neg_integer(),
          last_chain_sync_date: DateTime.t()
        }

  @enforce_keys [:status, :fee, :last_chain_sync_date]
  defstruct [:status, :fee, :last_chain_sync_date]

  @doc """
  Serialize message into binary
  """
  def serialize(%__MODULE__{
        status: status,
        fee: fee,
        last_chain_sync_date: last_chain_sync_date
      }) do
    <<serialize_status(status)::bitstring, fee::64,
      DateTime.to_unix(last_chain_sync_date, :millisecond)::64>>
  end

  defp serialize_status(:ok), do: <<0::8>>
  defp serialize_status({:error, :transaction_not_exists}), do: <<1::8>>

  defp serialize_status({:error, :invalid_execution, failure}),
    do: <<2::8, Failure.serialize(failure)::bitstring>>

  defp serialize_status({:error, :invalid_condition, subject}),
    do: <<3::8, VarInt.from_value(byte_size(subject))::binary, subject::binary>>

  defp serialize_status({:error, :insufficient_funds}), do: <<4::8>>

  defp serialize_status({:error, :parsing_error, reason}),
    do: <<5::8, VarInt.from_value(byte_size(reason))::binary, reason::binary>>

  defp serialize_status({:error, :timeout}), do: <<6::8>>

  @doc """
  Deserialize the encoded message
  """
  def deserialize(<<bin::bitstring>>) do
    {status, <<fee::64, unix_time::64, rest::bitstring>>} = deserialize_status(bin)

    {%__MODULE__{
       status: status,
       fee: fee,
       last_chain_sync_date: DateTime.from_unix!(unix_time, :millisecond)
     }, rest}
  end

  defp deserialize_status(<<0::8, rest::bitstring>>), do: {:ok, rest}

  defp deserialize_status(<<1::8, rest::bitstring>>),
    do: {{:error, :transaction_not_exists}, rest}

  defp deserialize_status(<<2::8, rest::bitstring>>) do
    {failure, rest} = Failure.deserialize(rest)
    {{:error, :invalid_execution, failure}, rest}
  end

  defp deserialize_status(<<3::8, rest::bitstring>>) do
    {subject_size, rest} = VarInt.get_value(rest)
    <<subject::binary-size(subject_size), rest::bitstring>> = rest
    {{:error, :invalid_condition, subject}, rest}
  end

  defp deserialize_status(<<4::8, rest::bitstring>>), do: {{:error, :insufficient_funds}, rest}

  defp deserialize_status(<<5::8, rest::bitstring>>) do
    {reason_size, rest} = VarInt.get_value(rest)
    <<reason::binary-size(reason_size), rest::bitstring>> = rest
    {{:error, :parsing_error, reason}, rest}
  end

  defp deserialize_status(<<6::8, rest::bitstring>>),
    do: {{:error, :timeout}, rest}
end
