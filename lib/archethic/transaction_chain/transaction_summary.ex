defmodule Archethic.TransactionChain.TransactionSummary do
  @moduledoc """
  Represents transaction header or extract to summarize it
  """

  @version 2

  defstruct [
    :timestamp,
    :address,
    :type,
    :fee,
    :validation_stamp_checksum,
    :genesis_address,
    movements_addresses: [],
    version: @version
  ]

  alias Archethic.Election

  alias Archethic.TransactionChain
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
  @spec from_transaction(
          transaction :: Transaction.t(),
          genesis_address :: binary(),
          version :: non_neg_integer()
        ) :: t()
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
                },
              recipients: recipients
            }
        },
        genesis_address,
        version \\ @version
      )
      when is_binary(genesis_address) do
    raw_stamp = validation_stamp |> ValidationStamp.serialize() |> Utils.wrap_binary()
    validation_stamp_checksum = :crypto.hash(:sha256, raw_stamp)

    movements_addresses =
      if version >= 2 do
        operations
        |> LedgerOperations.movement_addresses()
        |> Enum.concat(recipients)
      else
        LedgerOperations.movement_addresses(operations)
      end

    %__MODULE__{
      address: address,
      timestamp: timestamp,
      movements_addresses: movements_addresses,
      type: type,
      fee: fee,
      validation_stamp_checksum: validation_stamp_checksum,
      genesis_address: genesis_address,
      version: version
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

  @doc """
  Resolve movements addresses

  Before AEIP-21, we need to fetch the genesis address as movements are not resolved to the genesis addresses
  Hence this function is useful for self-repair transition for the AEIP-21 integration
  """
  @spec resolve_movements_addresses(t(), list(Node.t())) :: Enumerable.t() | list(binary())
  def resolve_movements_addresses(
        %__MODULE__{movements_addresses: addresses, version: version},
        node_list
      )
      when version <= 2 do
    addresses
    |> Task.async_stream(fn address ->
      storage_nodes = Election.chain_storage_nodes(address, node_list)

      case TransactionChain.fetch_genesis_address(address, storage_nodes) do
        {:ok, genesis_address} ->
          [genesis_address, address]

        _ ->
          [address]
      end
    end)
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Stream.flat_map(fn {:ok, res} -> res end)
  end

  def resolve_movements_addresses(%__MODULE__{movements_addresses: movements_addresses}),
    do: movements_addresses

  def equals?(
        _comparand = %__MODULE__{
          address: address1,
          type: type1,
          validation_stamp_checksum: checksum_1,
          movements_addresses: movements_addresses1,
          version: version1
        },
        _comparator = %__MODULE__{
          address: address2,
          type: type2,
          validation_stamp_checksum: checksum_2,
          movements_addresses: movements_addresses2,
          version: version2
        }
      )
      when address1 == address2 and type1 == type2 and checksum_1 == checksum_2 and
             version1 == version2 and version1 <= 2 do
    # During AEIP-21 deployment phases,
    # transaction summary from beacon and from transaction will differ
    # because some will included resolve movements address with or without genesis addresses
    # Hence we have to find a common factor as the comparand transaction summary movements addresses coming from the transaction's stamp

    movements_addresses1
    |> MapSet.new()
    |> MapSet.intersection(MapSet.new(movements_addresses2))
    |> MapSet.to_list() == movements_addresses1
  end

  def equals?(tx_summary1, tx_summary2), do: tx_summary1 == tx_summary2
end
