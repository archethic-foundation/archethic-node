defmodule Archethic.Mining.Error do
  @moduledoc """
  This struct holds the data about a validation that failed
  """

  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.Utils.VarInt
  alias Archethic.Utils.TypedEncoding

  @enforce_keys [:code, :message]
  defstruct [:code, :message, :data]

  @type error ::
          ValidationStamp.error()
          | :timeout
          | :consensus_not_reached
          | :transaction_in_mining

  @type context :: :invalid_transaction | :network_issue

  @type t :: %__MODULE__{
          code: integer(),
          message: String.t(),
          data: any()
        }

  @spec new(error :: error(), data :: any()) :: t()
  def new(error, data \\ nil)

  def new(error, data) do
    {code, message} = get_error_code_message(error)
    %__MODULE__{code: code, message: message, data: data}
  end

  defp get_error_code_message(:transaction_in_mining),
    do: {-30000, "Transaction already in mining with different data"}

  defp get_error_code_message(:invalid_pending_transaction),
    do: {-30100, "Invalid transaction data"}

  defp get_error_code_message(:insufficient_funds), do: {-31000, "Insufficient funds"}

  defp get_error_code_message(:invalid_inherit_constraints),
    do: {-31001, "Invalid contract inherit condition"}

  defp get_error_code_message(:invalid_contract_execution),
    do: {-31002, "Invalid contract execution"}

  defp get_error_code_message(:invalid_recipients_execution),
    do: {-31003, "Invalid recipients execution"}

  defp get_error_code_message(:recipients_not_distinct),
    do: {-31004, "Transaction recipients are not distinct"}

  defp get_error_code_message(:invalid_contract_context_inputs),
    do: {-31500, "Invalid contract context inputs"}

  defp get_error_code_message(:consensus_not_reached), do: {-31501, "Consensus not reached"}
  defp get_error_code_message(:timeout), do: {-31502, "Transaction validation timeout"}

  @doc """
  Return the context of the error.
  :invalid_transaction for error related to user transaction
  :network_issue for error related to network validation
  """
  @spec get_context(mining_error :: t()) :: context()
  def get_context(%__MODULE__{code: code}) when code <= -31500, do: :network_issue
  def get_context(_), do: :invalid_transaction

  @doc """
  Convert a mining error into a validation stamp error atom
  """
  @spec to_stamp_error(mining_error :: t()) :: ValidationStamp.error() | nil
  def to_stamp_error(%__MODULE__{code: -30100}), do: :invalid_pending_transaction
  def to_stamp_error(%__MODULE__{code: -31000}), do: :insufficient_funds
  def to_stamp_error(%__MODULE__{code: -31001}), do: :invalid_inherit_constraints
  def to_stamp_error(%__MODULE__{code: -31002}), do: :invalid_contract_execution
  def to_stamp_error(%__MODULE__{code: -31003}), do: :invalid_recipients_execution
  def to_stamp_error(%__MODULE__{code: -31004}), do: :recipients_not_distinct
  def to_stamp_error(%__MODULE__{code: -31500}), do: :invalid_contract_context_inputs
  def to_stamp_error(_), do: nil

  @doc """
  Serialize a Mining.Error in binary
  """
  @spec serialize(mining_error :: t()) :: bitstring()
  def serialize(%__MODULE__{code: code, message: message, data: data}) do
    <<-code::16, VarInt.from_value(byte_size(message))::binary, message::binary,
      TypedEncoding.serialize(data, :compact)::bitstring>>
  end

  @doc """
  Deserialize a binary into a Mining.Error
  """
  @spec deserialize(binary :: bitstring()) :: {mining_error :: t(), rest :: bitstring()}
  def deserialize(<<code::16, rest::bitstring>>) do
    {message_size, rest} = VarInt.get_value(rest)
    <<message::binary-size(message_size), rest::bitstring>> = rest
    {data, rest} = TypedEncoding.deserialize(rest, :compact)

    {%__MODULE__{code: -code, message: message, data: data}, rest}
  end
end
