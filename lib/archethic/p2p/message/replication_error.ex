defmodule Archethic.P2P.Message.ReplicationError do
  @moduledoc """
  Represents a replication error message
  """

  alias Archethic.Replication.TransactionValidator
  alias Archethic.Utils

  @enforce_keys [:address, :reason]
  defstruct [:address, :reason]

  @type t :: %__MODULE__{
          address: binary(),
          reason: reason()
        }

  @type reason :: TransactionValidator.error() | :transaction_already_exists

  @doc """
  Serialize a replication error message

        iex> %ReplicationError{
        ...> address: << 0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234,
        ...> 201, 172, 3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>,
        ...> reason: :transaction_already_exists
        ...>} |> ReplicationError.serialize()
        << 0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172, 3,
         195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251, 1>>

        iex> %ReplicationError{
        ...> address: << 0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234,
        ...> 201, 172, 3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>,
        ...> reason: :invalid_unspent_outputs
        ...>} |> ReplicationError.serialize()
        << 0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172, 3,
         195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251, 14>>

  """
  @spec serialize(%__MODULE__{}) :: <<_::32, _::_*8>>
  def serialize(%__MODULE__{address: address, reason: reason}) do
    <<address::binary, serialize_reason(reason)::8>>
  end

  @spec serialize_reason(reason()) :: non_neg_integer()
  def serialize_reason(:transaction_already_exists), do: 1
  def serialize_reason(:invalid_atomic_commitment), do: 2
  def serialize_reason(:invalid_node_election), do: 3
  def serialize_reason(:invalid_proof_of_work), do: 4
  def serialize_reason(:invalid_transaction_fee), do: 5
  def serialize_reason(:invalid_transaction_movements), do: 6
  def serialize_reason(:insufficient_funds), do: 7
  def serialize_reason(:invalid_chain), do: 8
  def serialize_reason(:invalid_transaction_with_inconsistencies), do: 9
  def serialize_reason(:invalid_contract_acceptance), do: 10
  def serialize_reason(:invalid_pending_transaction), do: 11
  def serialize_reason(:invalid_inherit_constraints), do: 12
  def serialize_reason(:invalid_validation_stamp_signature), do: 13
  def serialize_reason(:invalid_unspent_outputs), do: 14

  @doc """
  DeSerialize a replication error message

        iex> <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        ...>  3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251,  1>>
        ...> |> ReplicationError.deserialize()
        {
        %ReplicationError{
        address: <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14,187, 133,59, 234, 201, 172,
        3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>,
        reason: :transaction_already_exists
        },""}


        iex>  <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        ...>  3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251, 14>>
        ...> |> ReplicationError.deserialize()
        {
        %ReplicationError{
        address: <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14,187, 133, 59, 234, 201, 172,
        3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31,185, 73, 251>>,
        reason: :invalid_unspent_outputs
        },""}
  """
  @spec deserialize(bin :: bitstring) :: {%__MODULE__{}, bitstring()}
  def deserialize(bin) do
    {address, rest} = Utils.deserialize_address(bin)
    {reason, rest} = deserialize_reason(rest)

    {%__MODULE__{address: address, reason: reason}, rest}
  end

  @spec deserialize_reason(bin :: bitstring) :: {atom, bitstring}
  def deserialize_reason(<<nb::8, rest::bitstring>>), do: {error(nb), rest}

  @spec error(1..255) :: atom
  def error(1), do: :transaction_already_exists
  def error(2), do: :invalid_atomic_commitment
  def error(3), do: :invalid_node_election
  def error(4), do: :invalid_proof_of_work
  def error(5), do: :invalid_transaction_fee
  def error(6), do: :invalid_tranxaction_movements
  def error(7), do: :insufficient_funds
  def error(8), do: :invalid_chain
  def error(9), do: :invalid_transaction_with_inconsistencies
  def error(10), do: :invalid_contract_acceptance
  def error(11), do: :invalid_pending_transaction
  def error(12), do: :invalid_inherit_constraints
  def error(13), do: :invalid_validation_stamp_signature
  def error(14), do: :invalid_unspent_outputs
end
