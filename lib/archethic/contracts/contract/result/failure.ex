defmodule Archethic.Contracts.Contract.Failure do
  @moduledoc """
  This struct holds the data about an execution that failed
  """

  alias Archethic.Utils.VarInt
  alias Archethic.Utils.TypedEncoding

  @enforce_keys [:user_friendly_error]
  defstruct [:user_friendly_error, :error, stacktrace: [], logs: [], data: nil]

  @type error ::
          :state_exceed_threshold
          | :trigger_not_exists
          | :execution_raise
          | :execution_timeout
          | :contract_throw
          | :function_does_not_exist
          | :function_is_private
          | :function_timeout
          | :missing_condition

  @type t :: %__MODULE__{
          user_friendly_error: String.t(),
          error: error(),
          stacktrace: term(),
          logs: list(String.t()),
          data: term()
        }

  @doc """
  Serialize a Failure in binary without stacktrace or log
  """
  @spec serialize(failure :: t()) :: bitstring()
  def serialize(%__MODULE__{error: error, user_friendly_error: user_friendly_error, data: data}) do
    <<serialize_error(error)::8, VarInt.from_value(byte_size(user_friendly_error))::binary,
      user_friendly_error::binary, TypedEncoding.serialize(data, :compact)::bitstring>>
  end

  defp serialize_error(:state_exceed_threshold), do: 0
  defp serialize_error(:trigger_not_exists), do: 1
  defp serialize_error(:execution_raise), do: 2
  defp serialize_error(:execution_timeout), do: 3
  defp serialize_error(:contract_throw), do: 4
  defp serialize_error(:function_does_not_exist), do: 5
  defp serialize_error(:function_is_private), do: 6
  defp serialize_error(:function_timeout), do: 7
  defp serialize_error(:missing_condition), do: 8

  @doc """
  Deserialize a binary into a Failure
  """
  @spec deserialize(binary :: bitstring()) :: {failure :: t(), rest :: bitstring()}
  def deserialize(<<error::8, rest::bitstring>>) do
    {user_friendly_error_size, rest} = VarInt.get_value(rest)
    <<user_friendly_error::binary-size(user_friendly_error_size), rest::bitstring>> = rest
    {data, rest} = TypedEncoding.deserialize(rest, :compact)

    {%__MODULE__{
       error: deserialize_error(error),
       user_friendly_error: user_friendly_error,
       data: data
     }, rest}
  end

  defp deserialize_error(0), do: :state_exceed_threshold
  defp deserialize_error(1), do: :trigger_not_exists
  defp deserialize_error(2), do: :execution_raise
  defp deserialize_error(3), do: :execution_timeout
  defp deserialize_error(4), do: :contract_throw
  defp deserialize_error(5), do: :function_does_not_exist
  defp deserialize_error(6), do: :function_is_private
  defp deserialize_error(7), do: :function_timeout
  defp deserialize_error(8), do: :missing_condition
end
