defmodule Archethic.P2P.Message.ReplicationError do
  @moduledoc """
  Represents a replication error message
  """

  alias Archethic.Replication.TransactionValidator
  alias Archethic.Crypto
  alias Archethic.Mining
  alias Archethic.P2P.Message.Ok
  alias Archethic.Utils

  @enforce_keys [:address, :reason]
  defstruct [:address, :reason]

  @type t :: %__MODULE__{
          address: binary(),
          reason: reason()
        }

  @type reason ::
          TransactionValidator.error() | :transaction_already_exists | :invalid_validation_inputs

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(
        %__MODULE__{
          address: address,
          reason: reason
        },
        from
      ) do
    Mining.notify_replication_error(address, reason, from)
    %Ok{}
  end

  @doc """
  Serialize a replication error message

        iex> %ReplicationError{
        ...>   address:
        ...>     <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172, 3,
        ...>       195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>,
        ...>   reason: :transaction_already_exists
        ...> }
        ...> |> ReplicationError.serialize()
        <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172, 3, 195, 43,
          81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251, 1>>

        iex> %ReplicationError{
        ...>   address:
        ...>     <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172, 3,
        ...>       195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>,
        ...>   reason: :invalid_unspent_outputs
        ...> }
        ...> |> ReplicationError.serialize()
        <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172, 3, 195, 43,
          81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251, 14>>

  """
  @spec serialize(%__MODULE__{}) :: <<_::32, _::_*8>>
  def serialize(%__MODULE__{address: address, reason: reason}) do
    <<address::binary, serialize_reason(reason)::8>>
  end

  @spec serialize_reason(reason()) :: non_neg_integer()
  defp serialize_reason(:transaction_already_exists), do: 1
  defp serialize_reason(:invalid_atomic_commitment), do: 2
  defp serialize_reason(:invalid_node_election), do: 3
  defp serialize_reason(:invalid_proof_of_work), do: 4
  defp serialize_reason(:invalid_transaction_fee), do: 5
  defp serialize_reason(:invalid_transaction_movements), do: 6
  defp serialize_reason(:insufficient_funds), do: 7
  defp serialize_reason(:invalid_chain), do: 8
  defp serialize_reason(:invalid_transaction_with_inconsistencies), do: 9
  defp serialize_reason(:invalid_contract_acceptance), do: 10
  defp serialize_reason(:invalid_pending_transaction), do: 11
  defp serialize_reason(:invalid_inherit_constraints), do: 12
  defp serialize_reason(:invalid_validation_stamp_signature), do: 13
  defp serialize_reason(:invalid_unspent_outputs), do: 14
  defp serialize_reason(:invalid_recipients_execution), do: 15
  defp serialize_reason(:invalid_contract_execution), do: 16
  defp serialize_reason(:invalid_validation_inputs), do: 17
  defp serialize_reason(:invalid_contract_context_inputs), do: 18

  @doc """
  DeSerialize a replication error message

        iex> <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172, 3, 195,
        ...>   43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251, 1>>
        ...> |> ReplicationError.deserialize()
        {
          %ReplicationError{
            address:
              <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172, 3, 195,
                43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>,
            reason: :transaction_already_exists
          },
          ""
        }


        iex> <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172, 3, 195,
        ...>   43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251, 14>>
        ...> |> ReplicationError.deserialize()
        {
          %ReplicationError{
            address:
              <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172, 3, 195,
                43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>,
            reason: :invalid_unspent_outputs
          },
          ""
        }
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
  defp error(1), do: :transaction_already_exists
  defp error(2), do: :invalid_atomic_commitment
  defp error(3), do: :invalid_node_election
  defp error(4), do: :invalid_proof_of_work
  defp error(5), do: :invalid_transaction_fee
  defp error(6), do: :invalid_transaction_movements
  defp error(7), do: :insufficient_funds
  defp error(8), do: :invalid_chain
  defp error(9), do: :invalid_transaction_with_inconsistencies
  defp error(10), do: :invalid_contract_acceptance
  defp error(11), do: :invalid_pending_transaction
  defp error(12), do: :invalid_inherit_constraints
  defp error(13), do: :invalid_validation_stamp_signature
  defp error(14), do: :invalid_unspent_outputs
  defp error(15), do: :invalid_recipients_execution
  defp error(16), do: :invalid_contract_execution
  defp error(17), do: :invalid_validation_inputs
  defp error(18), do: :invalid_contract_context_inputs
end
