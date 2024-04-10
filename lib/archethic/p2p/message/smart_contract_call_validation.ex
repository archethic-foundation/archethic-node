defmodule Archethic.P2P.Message.SmartContractCallValidation do
  @moduledoc """
  Represents a module to attest the validation of a transaction towards a contract
  """

  @type t :: %__MODULE__{
          status: :ok | {:error, :transaction_not_exists | :invalid_execution},
          fee: non_neg_integer()
        }

  defstruct [:status, :fee]

  @doc """
  Serialize message into binary
  """
  def serialize(%__MODULE__{status: status, fee: fee}) do
    <<serialize_status(status)::8, fee::64>>
  end

  defp serialize_status(:ok), do: 0
  defp serialize_status({:error, :transaction_not_exists}), do: 1
  defp serialize_status({:error, :invalid_execution}), do: 2

  @doc """
  Deserialize the encoded message
  """
  def deserialize(<<status_byte::8, fee::64, rest::bitstring>>) do
    status = deserialize_status(status_byte)
    {%__MODULE__{status: status, fee: fee}, rest}
  end

  defp deserialize_status(0), do: :ok
  defp deserialize_status(1), do: {:error, :transaction_not_exists}
  defp deserialize_status(2), do: {:error, :invalid_execution}
end
