defmodule Archethic.P2P.Message.ReplicationError do
  @moduledoc """
  Represents a replication error message
  """

  alias Archethic.Replication.TransactionValidator

  @enforce_keys [:address, :reason]
  defstruct [:address, :reason]

  @type reason ::
          TransactionValidator.error() | :transaction_already_exists

  @type t :: %__MODULE__{
          address: binary(),
          reason: reason()
        }

  @doc """
  Serialize an error reason
  """
  @spec serialize_reason(reason()) :: non_neg_integer()
  def serialize_reason(:transaction_already_exists), do: 1
  def serialize_reason(:invalid_atomic_commitment), do: 2
  def serialize_reason(:invalid_node_election), do: 3
  def serialize_reason(:invalid_proof_of_work), do: 4
  def serialize_reason(:invalid_transaction_fee), do: 5
  def serialize_reason(:invalid_transaction_movements), do: 6
  def serialize_reason(:unsufficient_funds), do: 7
  def serialize_reason(:invalid_chain), do: 8
  def serialize_reason(:invalid_transaction_with_inconsistencies), do: 9
  def serialize_reason(:invalid_contract_acceptance), do: 10
  def serialize_reason({:transaction_error, :pending_transaction_validation}), do: 11
  def serialize_reason({:transaction_error, :contract_validation}), do: 12
  def serialize_reason({:transaction_error, :oracle_validation}), do: 13

  @doc """
  Deserialize an error reason
  """
  @spec deserialize_reason(non_neg_integer()) :: reason()
  def deserialize_reason(1), do: :transaction_already_exists
  def deserialize_reason(2), do: :invalid_atomic_commitment
  def deserialize_reason(3), do: :invalid_node_election
  def deserialize_reason(4), do: :invalid_proof_of_work
  def deserialize_reason(5), do: :invalid_transaction_fee
  def deserialize_reason(6), do: :invalid_tranxaction_movements
  def deserialize_reason(7), do: :unsufficient_funds
  def deserialize_reason(8), do: :invalid_chain
  def deserialize_reason(9), do: :invalid_transaction_with_inconsistencies
  def deserialize_reason(10), do: :invalid_contract_acceptance
  def deserialize_reason(11), do: {:transaction_error, :pending_transaction}
  def deserialize_reason(12), do: {:transaction_error, :contract_validation}
  def deserialize_reason(13), do: {:transaction_error, :oracle_validation}
end
