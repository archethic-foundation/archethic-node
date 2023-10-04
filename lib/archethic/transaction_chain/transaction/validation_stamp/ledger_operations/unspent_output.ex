defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput do
  @moduledoc """
  Represents an unspent output from a transaction.
  """
  defstruct [:amount, :from, :type, :timestamp, :encoded_payload, reward?: false]

  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement.Type,
    as: TransactionMovementType

  alias Archethic.Utils

  @type t :: %__MODULE__{
          amount: non_neg_integer(),
          from: Crypto.versioned_hash(),
          type: TransactionMovementType.t() | :state,
          timestamp: DateTime.t(),
          encoded_payload: nil | binary()
        }

  @doc """
  Serialize unspent output into binary format
  """
  @spec serialize(utxo :: t(), protocol_version :: non_neg_integer()) :: bitstring()
  def serialize(
        %__MODULE__{
          from: from,
          amount: amount,
          type: type,
          timestamp: timestamp
        },
        protocol_version
      )
      when protocol_version < 4 do
    <<from::binary, amount::64, DateTime.to_unix(timestamp, :millisecond)::64,
      TransactionMovementType.serialize(type)::binary>>
  end

  # protocol_version 4+
  def serialize(
        %__MODULE__{type: :state, encoded_payload: encoded_payload},
        _protocol_version
      ) do
    encoded_payload_size =
      encoded_payload
      |> byte_size()
      |> Utils.VarInt.from_value()

    <<0::8, encoded_payload_size::binary, encoded_payload::binary>>
  end

  def serialize(
        %__MODULE__{
          from: from,
          amount: amount,
          type: type,
          timestamp: timestamp
        },
        _protocol_version
      ) do
    <<1::8, from::binary, amount::64, DateTime.to_unix(timestamp, :millisecond)::64,
      TransactionMovementType.serialize(type)::binary>>
  end

  @doc """
  Deserialize an encoded unspent output
  """
  @spec deserialize(data :: bitstring(), protocol_version :: non_neg_integer()) ::
          {t(), bitstring}
  def deserialize(data, protocol_version) when protocol_version < 4 do
    {address, <<amount::64, timestamp::64, rest::bitstring>>} = Utils.deserialize_address(data)
    {type, rest} = TransactionMovementType.deserialize(rest)

    {
      %__MODULE__{
        from: address,
        amount: amount,
        type: type,
        timestamp: DateTime.from_unix!(timestamp, :millisecond)
      },
      rest
    }
  end

  # protocol version 4+
  def deserialize(<<0::8, rest::bitstring>>, _protocol_version) when is_bitstring(rest) do
    {encoded_payload_size, rest} = Utils.VarInt.get_value(rest)
    <<encoded_payload::binary-size(encoded_payload_size), rest::bitstring>> = rest

    {
      %__MODULE__{
        type: :state,
        encoded_payload: encoded_payload
      },
      rest
    }
  end

  def deserialize(<<1::8, rest::bitstring>>, _protocol_version) when is_bitstring(rest) do
    {address, <<amount::64, timestamp::64, rest::bitstring>>} = Utils.deserialize_address(rest)
    {type, rest} = TransactionMovementType.deserialize(rest)

    {
      %__MODULE__{
        from: address,
        amount: amount,
        type: type,
        timestamp: DateTime.from_unix!(timestamp, :millisecond)
      },
      rest
    }
  end

  @doc """
  Build %UnspentOutput struct from map

  ## Examples

      iex> %{
      ...>  from:  <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      ...>    159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
      ...>  amount: 1_050_000_000,
      ...>  type: :UCO,
      ...>  timestamp: ~U[2022-10-11 07:27:22.815Z]
      ...>  } |> UnspentOutput.cast()
      %UnspentOutput{
        from: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        amount: 1_050_000_000,
        type: :UCO,
        reward?: false,
        timestamp: ~U[2022-10-11 07:27:22.815Z],
      }

      iex> %{
      ...>  from: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45,
      ...>    68, 194, 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
      ...>  amount: 1_050_000_000,
      ...>  type: {:token, <<0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
      ...>    197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>, 0}
      ...> } |> UnspentOutput.cast()
      %UnspentOutput{
        from: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        amount: 1_050_000_000,
        type: {:token, <<0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>, 0 },
        reward?: false,
        timestamp: nil
      }
  """
  @spec cast(map()) :: __MODULE__.t()
  def cast(unspent_output = %{}) do
    %__MODULE__{
      from: Map.get(unspent_output, :from),
      encoded_payload: Map.get(unspent_output, :encoded_payload),
      amount: Map.get(unspent_output, :amount),
      type: Map.get(unspent_output, :type),
      timestamp: Map.get(unspent_output, :timestamp)
    }
  end

  @doc """
  Convert %UnspentOutput{} Struct to a Map

  ## Examples

      iex> %UnspentOutput{
      ...> from: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
      ...> amount: 1_050_000_000,
      ...> type: :UCO,
      ...> reward?: false,
      ...> timestamp: ~U[2022-10-11 07:27:22.815Z],
      ...> }|> UnspentOutput.to_map()
      %{
        from:  <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        amount: 1_050_000_000,
        type: "UCO",
        reward?: false,
        timestamp: ~U[2022-10-11 07:27:22.815Z]
      }

      iex> %UnspentOutput{
      ...>  from: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45,
      ...>    68, 194, 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
      ...>  amount: 1_050_000_000,
      ...>  type: {:token, <<0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185,
      ...>    71, 140, 74,  197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>, 0 },
      ...> } |> UnspentOutput.to_map()
      %{
        from: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68,
        194,159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        amount: 1_050_000_000,
        type: "token",
        token_address: <<0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71,
        140,74,197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
        token_id: 0,
        reward?: false,
        timestamp: nil
      }
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{
        from: from,
        amount: amount,
        type: :UCO,
        reward?: reward,
        timestamp: timestamp
      }) do
    %{
      from: from,
      amount: amount,
      type: "UCO",
      reward?: reward,
      timestamp: timestamp
    }
  end

  def to_map(%__MODULE__{
        from: from,
        amount: amount,
        type: {:token, token_address, token_id},
        reward?: reward,
        timestamp: timestamp
      }) do
    %{
      from: from,
      amount: amount,
      type: "token",
      token_address: token_address,
      token_id: token_id,
      reward?: reward,
      timestamp: timestamp
    }
  end
end
