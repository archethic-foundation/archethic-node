defmodule Archethic.TransactionChain.TransactionSummary do
  @moduledoc """
  Represents transaction header or extract to summarize it
  """
  defstruct [
    :timestamp,
    :address,
    :type,
    :fee,
    :validation_stamp_checksum,
    :genesis_address,
    movements_addresses: [],
    version: 2
  ]

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  @type t :: %__MODULE__{
          version: non_neg_integer(),
          timestamp: DateTime.t(),
          address: binary(),
          movements_addresses: list(binary()),
          type: Transaction.transaction_type(),
          fee: pos_integer(),
          validation_stamp_checksum: binary(),
          genesis_address: binary()
        }

  @doc """
  Convert a transaction into transaction info
  """
  @spec from_transaction(transaction :: Transaction.t(), genesis_address :: binary()) :: t()
  def from_transaction(
        %Transaction{
          address: address,
          type: type,
          validation_stamp:
            validation_stamp = %ValidationStamp{
              timestamp: timestamp,
              ledger_operations:
                operations = %LedgerOperations{
                  fee: fee
                }
            }
        },
        genesis_address
      )
      when is_binary(genesis_address) do
    raw_stamp = validation_stamp |> ValidationStamp.serialize() |> Utils.wrap_binary()
    validation_stamp_checksum = :crypto.hash(:sha256, raw_stamp)

    %__MODULE__{
      address: address,
      timestamp: timestamp,
      movements_addresses: LedgerOperations.movement_addresses(operations),
      type: type,
      fee: fee,
      validation_stamp_checksum: validation_stamp_checksum,
      genesis_address: genesis_address
    }
  end

  @doc """
  Serialize into binary format
  """
  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{
        version: 1,
        address: address,
        timestamp: timestamp,
        type: type,
        movements_addresses: movements_addresses,
        fee: fee,
        validation_stamp_checksum: validation_stamp_checksum
      }) do
    encoded_movement_addresses_len = length(movements_addresses) |> VarInt.from_value()

    <<1::8, address::binary, DateTime.to_unix(timestamp, :millisecond)::64,
      Transaction.serialize_type(type), fee::64, encoded_movement_addresses_len::binary,
      :erlang.list_to_binary(movements_addresses)::binary, validation_stamp_checksum::binary>>
  end

  def serialize(%__MODULE__{
        version: version,
        address: address,
        timestamp: timestamp,
        type: type,
        movements_addresses: movements_addresses,
        fee: fee,
        validation_stamp_checksum: validation_stamp_checksum,
        genesis_address: genesis_address
      }) do
    encoded_movement_addresses_len = length(movements_addresses) |> VarInt.from_value()

    <<version::8, address::binary, DateTime.to_unix(timestamp, :millisecond)::64,
      Transaction.serialize_type(type), fee::64, encoded_movement_addresses_len::binary,
      :erlang.list_to_binary(movements_addresses)::binary, validation_stamp_checksum::binary,
      genesis_address::binary>>
  end

  @doc """
  Deserialize an encoded TransactionSummary
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<1::8, rest::bitstring>>) do
    {address, <<timestamp::64, type::8, fee::64, rest::bitstring>>} =
      Utils.deserialize_address(rest)

    {nb_movements, rest} = rest |> VarInt.get_value()

    {addresses, <<validation_stamp_checksum::binary-size(32), rest::bitstring>>} =
      Utils.deserialize_addresses(rest, nb_movements, [])

    {
      %__MODULE__{
        version: 1,
        address: address,
        timestamp: DateTime.from_unix!(timestamp, :millisecond),
        type: Transaction.parse_type(type),
        movements_addresses: addresses,
        fee: fee,
        validation_stamp_checksum: validation_stamp_checksum
      },
      rest
    }
  end

  def deserialize(<<version::8, rest::bitstring>>) do
    {address, <<timestamp::64, type::8, fee::64, rest::bitstring>>} =
      Utils.deserialize_address(rest)

    {nb_movements, rest} = rest |> VarInt.get_value()

    {addresses, <<validation_stamp_checksum::binary-size(32), rest::bitstring>>} =
      Utils.deserialize_addresses(rest, nb_movements, [])

    {genesis_address, rest} = Utils.deserialize_address(rest)

    {
      %__MODULE__{
        version: version,
        address: address,
        timestamp: DateTime.from_unix!(timestamp, :millisecond),
        type: Transaction.parse_type(type),
        movements_addresses: addresses,
        fee: fee,
        validation_stamp_checksum: validation_stamp_checksum,
        genesis_address: genesis_address
      },
      rest
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{
        address: address,
        timestamp: timestamp,
        type: type,
        movements_addresses: movements_addresses,
        fee: fee,
        validation_stamp_checksum: validation_stamp_checksum,
        genesis_address: genesis_address
      }) do
    %{
      address: address,
      timestamp: timestamp,
      type: Atom.to_string(type),
      movements_addresses: movements_addresses,
      fee: fee,
      validation_stamp_checksum: validation_stamp_checksum,
      genesis_address: genesis_address
    }
  end

  @spec cast(map()) :: t()
  def cast(%{
        address: address,
        timestamp: timestamp,
        type: type,
        movements_addresses: movements_addresses,
        fee: fee,
        validation_stamp_checksum: validation_stamp_checksum,
        genesis_address: genesis_address
      }) do
    %__MODULE__{
      address: address,
      timestamp: timestamp,
      type: String.to_atom(type),
      movements_addresses: movements_addresses,
      fee: fee,
      validation_stamp_checksum: validation_stamp_checksum,
      genesis_address: genesis_address
    }
  end

  @doc """
  Apply a tranformation of a transaction summary based on the blockchain version
  """
  @spec transform(binary(), t()) :: t()
  def transform(_, tx_summary), do: tx_summary
end
