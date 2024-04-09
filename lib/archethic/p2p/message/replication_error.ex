defmodule Archethic.P2P.Message.ReplicationError do
  @moduledoc """
  Represents a replication error message
  """

  alias Archethic.Replication.TransactionValidator
  alias Archethic.Crypto
  alias Archethic.Mining
  alias Archethic.P2P.Message.Ok
  alias Archethic.Utils
  alias Archethic.Utils.TypedEncoding
  alias Archethic.Utils.VarInt

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
  @spec serialize(%__MODULE__{}) :: bitstring()
  def serialize(%__MODULE__{address: address, reason: reason}) do
    <<address::binary, serialize_reason(reason)::bitstring>>
  end

  defp serialize_reason(:transaction_already_exists), do: <<1::8>>
  defp serialize_reason(:invalid_atomic_commitment), do: <<2::8>>
  defp serialize_reason(:invalid_node_election), do: <<3::8>>
  defp serialize_reason(:invalid_proof_of_work), do: <<4::8>>
  defp serialize_reason(:invalid_transaction_fee), do: <<5::8>>
  defp serialize_reason(:invalid_transaction_movements), do: <<6::8>>
  defp serialize_reason(:insufficient_funds), do: <<7::8>>
  defp serialize_reason(:invalid_chain), do: <<8::8>>
  defp serialize_reason(:invalid_transaction_with_inconsistencies), do: <<9::8>>
  defp serialize_reason(:invalid_pending_transaction), do: <<10::8>>
  defp serialize_reason(:invalid_inherit_constraints), do: <<11::8>>
  defp serialize_reason(:invalid_validation_stamp_signature), do: <<12::8>>
  defp serialize_reason(:invalid_unspent_outputs), do: <<13::8>>

  defp serialize_reason({:invalid_recipients_execution, message, data}) do
    message_bin = <<VarInt.from_value(byte_size(message))::binary, message::binary>>
    <<14::8, message_bin::binary, TypedEncoding.serialize(data, :compact)::bitstring>>
  end

  defp serialize_reason(:invalid_contract_execution), do: <<15::8>>
  defp serialize_reason(:invalid_validation_inputs), do: <<16::8>>
  defp serialize_reason(:invalid_contract_context_inputs), do: <<17::8>>

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

  defp deserialize_reason(<<1::8, rest::bitstring>>), do: {:transaction_already_exists, rest}
  defp deserialize_reason(<<2::8, rest::bitstring>>), do: {:invalid_atomic_commitment, rest}
  defp deserialize_reason(<<3::8, rest::bitstring>>), do: {:invalid_node_election, rest}
  defp deserialize_reason(<<4::8, rest::bitstring>>), do: {:invalid_proof_of_work, rest}
  defp deserialize_reason(<<5::8, rest::bitstring>>), do: {:invalid_transaction_fee, rest}
  defp deserialize_reason(<<6::8, rest::bitstring>>), do: {:invalid_transaction_movements, rest}
  defp deserialize_reason(<<7::8, rest::bitstring>>), do: {:insufficient_funds, rest}
  defp deserialize_reason(<<8::8, rest::bitstring>>), do: {:invalid_chain, rest}

  defp deserialize_reason(<<9::8, rest::bitstring>>),
    do: {:invalid_transaction_with_inconsistencies, rest}

  defp deserialize_reason(<<10::8, rest::bitstring>>), do: {:invalid_pending_transaction, rest}
  defp deserialize_reason(<<11::8, rest::bitstring>>), do: {:invalid_inherit_constraints, rest}

  defp deserialize_reason(<<12::8, rest::bitstring>>),
    do: {:invalid_validation_stamp_signature, rest}

  defp deserialize_reason(<<13::8, rest::bitstring>>), do: {:invalid_unspent_outputs, rest}

  defp deserialize_reason(<<14::8, rest::bitstring>>) do
    {message_length, rest} = VarInt.get_value(rest)
    <<message::binary-size(message_length), rest::bitstring>> = rest
    {data, rest} = TypedEncoding.deserialize(rest, :compact)
    {{:invalid_recipients_execution, message, data}, rest}
  end

  defp deserialize_reason(<<15::8, rest::bitstring>>), do: {:invalid_contract_execution, rest}
  defp deserialize_reason(<<16::8, rest::bitstring>>), do: {:invalid_validation_inputs, rest}

  defp deserialize_reason(<<17::8, rest::bitstring>>),
    do: {:invalid_contract_context_inputs, rest}
end
