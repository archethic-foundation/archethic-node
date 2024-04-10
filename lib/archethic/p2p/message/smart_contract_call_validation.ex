defmodule Archethic.P2P.Message.SmartContractCallValidation do
  @moduledoc """
  Response of ValidateSmartContractCall message.
  """

  @typedoc """
  `latest_validation_time` is used for conflict resolution. If there are no transaction yet, use epoch.
  """
  @type t :: %__MODULE__{
          status: :ok | {:error, :transaction_not_exists | :invalid_execution},
          fee: non_neg_integer(),
          latest_validation_time: DateTime.t()
        }

  @enforce_keys [:status, :fee, :latest_validation_time]
  defstruct [:status, :fee, :latest_validation_time]

  @doc """
  Serialize message
  """
  def serialize(%__MODULE__{
        status: status,
        fee: fee,
        latest_validation_time: latest_validation_time
      }) do
    <<serialize_status(status)::8, fee::64,
      DateTime.to_unix(latest_validation_time, :millisecond)::64>>
  end

  @doc """
  Deserialize binary
  """
  def deserialize(<<status_byte::8, fee::64, unix_time::64, rest::bitstring>>) do
    status = deserialize_status(status_byte)

    {%__MODULE__{
       status: status,
       fee: fee,
       latest_validation_time: DateTime.from_unix!(unix_time, :millisecond)
     }, rest}
  end

  defp serialize_status(:ok), do: 0
  defp serialize_status({:error, :transaction_not_exists}), do: 1
  defp serialize_status({:error, :invalid_execution}), do: 2

  defp deserialize_status(0), do: :ok
  defp deserialize_status(1), do: {:error, :transaction_not_exists}
  defp deserialize_status(2), do: {:error, :invalid_execution}
end
