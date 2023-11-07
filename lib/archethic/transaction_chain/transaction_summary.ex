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
    movements_addresses: [],
    version: 1
  ]

  alias Archethic.Election

  alias Archethic.P2P

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
          validation_stamp_checksum: binary()
        }

  @doc """
  Convert a transaction into transaction info
  """
  @spec from_transaction(Transaction.t()) :: t()
  def from_transaction(%Transaction{
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
      }) do
    raw_stamp = validation_stamp |> ValidationStamp.serialize() |> Utils.wrap_binary()
    validation_stamp_checksum = :crypto.hash(:sha256, raw_stamp)

    %__MODULE__{
      address: address,
      timestamp: timestamp,
      movements_addresses: LedgerOperations.movement_addresses(operations),
      type: type,
      fee: fee,
      validation_stamp_checksum: validation_stamp_checksum
    }
  end

  @doc """
  Serialize into binary format

  ## Examples

        iex> %TransactionSummary{
        ...>   address:  <<0, 0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
        ...>     168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
        ...>   timestamp: ~U[2020-06-25 15:11:53Z],
        ...>   type: :transfer,
        ...>   movements_addresses: [
        ...>      <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
        ...>        99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>
        ...>   ],
        ...>   fee: 10_000_000,
        ...>   validation_stamp_checksum: <<17, 8, 18, 246, 127, 161, 225, 240, 17, 127, 111, 61, 112, 36, 28, 26, 66,
        ...>    167, 176, 119, 17, 169, 60, 36, 119, 204, 81, 109, 144, 66, 249, 219>>
        ...> }
        ...> |> TransactionSummary.serialize()
        <<
        # Version
        1,
        # Address
        0, 0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
        168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247,
        # Timestamp
        0, 0, 1, 114, 236, 9, 2, 168,
        # Type
        253,
        # Fee,
        0, 0, 0, 0, 0, 152, 150, 128,
        # Nb movements addresses
        1, 1,
        # Movement address
        0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
        99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12,
        # Validation stamp checksum
        17, 8, 18, 246, 127, 161, 225, 240, 17, 127, 111, 61, 112, 36, 28, 26, 66,
        167, 176, 119, 17, 169, 60, 36, 119, 204, 81, 109, 144, 66, 249, 219
        >>
  """
  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{
        version: version,
        address: address,
        timestamp: timestamp,
        type: type,
        movements_addresses: movements_addresses,
        fee: fee,
        validation_stamp_checksum: validation_stamp_checksum
      }) do
    encoded_movement_addresses_len = length(movements_addresses) |> VarInt.from_value()

    <<version::8, address::binary, DateTime.to_unix(timestamp, :millisecond)::64,
      Transaction.serialize_type(type), fee::64, encoded_movement_addresses_len::binary,
      :erlang.list_to_binary(movements_addresses)::binary, validation_stamp_checksum::binary>>
  end

  @doc """
  Deserialize an encoded TransactionSummary

  ## Example

      iex> <<1, 0, 0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
      ...> 168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247, 0, 0, 1, 114, 236, 9, 2, 168,
      ...> 253, 0, 0, 0, 0, 0, 152, 150, 128,
      ...> 1, 1, 0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...> 99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12,
      ...> 17, 8, 18, 246, 127, 161, 225, 240, 17, 127, 111, 61, 112, 36, 28, 26, 66,
      ...> 167, 176, 119, 17, 169, 60, 36, 119, 204, 81, 109, 144, 66, 249, 219>>
      ...> |> TransactionSummary.deserialize()
      {
        %TransactionSummary{
          version: 1,
          address:  <<0, 0, 11, 4, 226, 118, 242, 59, 165, 128, 69, 40, 228, 121, 127, 37, 154, 199,
              168, 212, 53, 82, 220, 22, 56, 222, 223, 127, 16, 172, 142, 218, 41, 247>>,
            timestamp: ~U[2020-06-25 15:11:53.000Z],
            type: :transfer,
            movements_addresses: [
              <<0, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
                99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>
            ],
          fee: 10_000_000,
          validation_stamp_checksum: <<17, 8, 18, 246, 127, 161, 225, 240, 17, 127, 111, 61, 112, 36, 28, 26, 66,
        167, 176, 119, 17, 169, 60, 36, 119, 204, 81, 109, 144, 66, 249, 219>>
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<version::8, rest::bitstring>>) do
    {address, <<timestamp::64, type::8, fee::64, rest::bitstring>>} =
      Utils.deserialize_address(rest)

    {nb_movements, rest} = rest |> VarInt.get_value()

    {addresses, <<validation_stamp_checksum::binary-size(32), rest::bitstring>>} =
      Utils.deserialize_addresses(rest, nb_movements, [])

    {
      %__MODULE__{
        version: version,
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

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{
        address: address,
        timestamp: timestamp,
        type: type,
        movements_addresses: movements_addresses,
        fee: fee,
        validation_stamp_checksum: validation_stamp_checksum
      }) do
    %{
      address: address,
      timestamp: timestamp,
      type: Atom.to_string(type),
      movements_addresses: movements_addresses,
      fee: fee,
      validation_stamp_checksum: validation_stamp_checksum
    }
  end

  @spec cast(map()) :: t()
  def cast(%{
        address: address,
        timestamp: timestamp,
        type: type,
        movements_addresses: movements_addresses,
        fee: fee,
        validation_stamp_checksum: validation_stamp_checksum
      }) do
    %__MODULE__{
      address: address,
      timestamp: timestamp,
      type: String.to_atom(type),
      movements_addresses: movements_addresses,
      fee: fee,
      validation_stamp_checksum: validation_stamp_checksum
    }
  end

  @doc """
  Apply a tranformation of a transaction summary based on the blockchain version
  """
  @spec transform(binary(), t()) :: t()
  def transform("1.1.0", tx_summary = %__MODULE__{version: 1}), do: tx_summary

  def transform("1.1.0", %__MODULE__{address: address}) do
    nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    {:ok, tx} = TransactionChain.fetch_transaction(address, nodes)
    from_transaction(tx)
  end

  def transform(_, tx_summary), do: tx_summary

  @doc """
  This function will be used during the summary day of 1.1.0 upgrade. This function can be deleted after the upgrade.
  Migrate this function into files 1.1.0-migrate_old_tx_summaries
  Deserialize an old version of transaction summary
  """
  @spec deserialize_old(bitstring()) :: {t(), bitstring()}
  def deserialize_old(data) do
    {address, <<timestamp::64, type::8, fee::64, rest::bitstring>>} =
      Utils.deserialize_address(data)

    {nb_movements, rest} = rest |> VarInt.get_value()
    {addresses, rest} = Utils.deserialize_addresses(rest, nb_movements, [])

    {
      %__MODULE__{
        version: 0,
        address: address,
        timestamp: DateTime.from_unix!(timestamp, :millisecond),
        type: Transaction.parse_type(type),
        movements_addresses: addresses,
        fee: fee,
        validation_stamp_checksum: ""
      },
      rest
    }
  end
end
