defmodule Archethic.TransactionChain.VersionedTransactionInput do
  @moduledoc """
  Represent a transaction input linked to a protocol version
  """

  defstruct [:protocol_version, :input]

  alias Archethic.TransactionChain.TransactionInput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  @type t :: %__MODULE__{
          protocol_version: pos_integer(),
          input: TransactionInput.t()
        }

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{
        protocol_version: protocol_version,
        input: input
      }) do
    TransactionInput.to_map(input, protocol_version)
  end

  @doc """
  Convert an VersionedUnspentOutput into a VersionedTransactionInput struct
  """
  @spec from_utxo(VersionedUnspentOutput.t()) :: t()
  def from_utxo(%VersionedUnspentOutput{protocol_version: protocol_version, unspent_output: utxo}) do
    %__MODULE__{
      protocol_version: protocol_version,
      input: TransactionInput.from_utxo(utxo)
    }
  end

  @doc """
  Mark the input as spent if it is not a member of the genesis inputs
  """
  @spec set_spent(t(), list(t())) :: t()
  def set_spent(versioned_input = %__MODULE__{input: input}, genesis_inputs) do
    %{
      versioned_input
      | input: TransactionInput.set_spent(input, genesis_inputs |> Enum.map(& &1.input))
    }
  end

  @doc """
  Unwrap a list of VersionedTransactionInput into a list of UnspentOutput
  """
  @spec unwrap_inputs(versioned_inputs :: list(t())) :: list(TransactionInput.t())
  def unwrap_inputs(versioned_inputs),
    do: Enum.map(versioned_inputs, &unwrap_input/1)

  @doc """
  Unwrap a VersionedTransactionInput into an TransactionInput
  """
  @spec unwrap_input(versioned_input :: t()) :: TransactionInput.t()
  def unwrap_input(%__MODULE__{input: input}), do: input

  @spec serialize(t()) :: bitstring()
  def serialize(
        input = %__MODULE__{
          protocol_version: protocol_version,
          input: %TransactionInput{type: :state}
        }
      )
      when protocol_version < 7,
      # Before AEIP-21 call where not serialized in unspent output so the serialization / deserialization
      # does not work with protocol version < 7
      do: serialize(%__MODULE__{input | protocol_version: 7})

  def serialize(%__MODULE__{
        protocol_version: protocol_version,
        input: input = %TransactionInput{}
      }) do
    <<protocol_version::32, TransactionInput.serialize(input, protocol_version)::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<protocol_version::32, rest::bitstring>>) do
    {input, rest} = TransactionInput.deserialize(rest, protocol_version)

    {
      %__MODULE__{
        protocol_version: protocol_version,
        input: input
      },
      rest
    }
  end
end
