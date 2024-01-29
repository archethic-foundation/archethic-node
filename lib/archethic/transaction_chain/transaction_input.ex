defmodule Archethic.TransactionChain.TransactionInput do
  @moduledoc """
  Represents an transaction sent to an account either spent or unspent
  """
  defstruct [:from, :amount, :type, :timestamp, :encoded_payload, spent?: false, reward?: false]

  alias Archethic.Contracts.Contract.State
  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement.Type,
    as: TransactionMovementType

  alias Archethic.Utils

  @type t() :: %__MODULE__{
          from: Crypto.versioned_hash(),
          amount: pos_integer() | nil,
          spent?: boolean(),
          type: TransactionMovementType.t() | :call | :state,
          timestamp: DateTime.t(),
          reward?: boolean(),
          encoded_payload: nil | binary()
        }

  @doc """
  Serialize an account input into binary
  """
  @spec serialize(tx_input :: t(), protocol_version :: pos_integer()) :: bitstring()
  def serialize(
        %__MODULE__{
          from: from,
          amount: amount,
          type: type,
          spent?: spent?,
          reward?: reward?,
          timestamp: timestamp
        },
        protocol_version
      )
      when protocol_version < 6 do
    case type do
      :call ->
        <<from::binary, 0::1, 0::1, DateTime.to_unix(timestamp)::32>>

      type ->
        spend_bit = if spent?, do: 1, else: 0
        reward_bit = if reward?, do: 1, else: 0

        <<from::binary, 1::1, spend_bit::1, reward_bit::1, amount::64,
          TransactionMovementType.serialize(type)::binary, DateTime.to_unix(timestamp)::32>>
    end
  end

  def serialize(
        %__MODULE__{
          from: from,
          type: type,
          timestamp: timestamp,
          amount: amount,
          encoded_payload: encoded_payload,
          spent?: spent?
        },
        _protocol_version
      ) do
    spent_bit = if spent?, do: 1, else: 0

    type_bin =
      case type do
        :state ->
          encoded_payload_size = encoded_payload |> bit_size() |> Utils.VarInt.from_value()
          <<0::8, encoded_payload_size::binary, encoded_payload::binary>>

        :call ->
          <<1::8>>

        _ ->
          type_bin = TransactionMovementType.serialize(type)
          amount_bin = Utils.VarInt.from_value(amount)
          <<2::8, type_bin::binary, amount_bin::binary>>
      end

    <<from::binary, DateTime.to_unix(timestamp, :millisecond)::64, spent_bit::1,
      type_bin::binary>>
  end

  @doc """
  Deserialize an encoded TransactionInput
  """
  @spec deserialize(bitstring(), protocol_version :: pos_integer()) ::
          {__MODULE__.t(), bitstring()}
  def deserialize(data, protocol_version) when protocol_version < 6 do
    {address, <<type_bit::1, spent_bit::1, rest::bitstring>>} = Utils.deserialize_address(data)

    spent? = if spent_bit == 1, do: true, else: false

    case type_bit do
      0 ->
        <<timestamp::32, rest::bitstring>> = rest

        {
          %__MODULE__{
            from: address,
            spent?: spent?,
            reward?: false,
            type: :call,
            timestamp: DateTime.from_unix!(timestamp)
          },
          rest
        }

      1 ->
        <<reward_bit::1, amount::64, rest::bitstring>> = rest
        reward? = if reward_bit == 1, do: true, else: false

        {movement_type, <<timestamp::32, rest::bitstring>>} =
          TransactionMovementType.deserialize(rest)

        {
          %__MODULE__{
            from: address,
            spent?: spent?,
            amount: amount,
            type: movement_type,
            reward?: reward?,
            timestamp: DateTime.from_unix!(timestamp)
          },
          rest
        }
    end
  end

  def deserialize(data, _protocol_version) do
    {from, <<timestamp::64, spent_bit::1, rest::bitstring>>} = Utils.deserialize_address(data)

    input = %__MODULE__{
      from: from,
      timestamp: DateTime.from_unix!(timestamp, :millisecond),
      spent?: spent_bit == 1
    }

    case rest do
      <<0::8, rest::bitstring>> ->
        {payload_size, rest} = Utils.VarInt.get_value(rest)
        <<encoded_payload::binary-size(payload_size), rest::bitstring>> = rest

        {
          %{input | type: :state, encoded_payload: encoded_payload},
          rest
        }

      <<1::8, rest::bitstring>> ->
        {
          %{input | type: :call},
          rest
        }

      <<2::8, rest::bitstring>> ->
        {type, rest} = TransactionMovementType.deserialize(rest)
        {amount, rest} = Utils.VarInt.get_value(rest)

        {
          %{input | type: type, amount: amount},
          rest
        }
    end
  end

  @spec cast(map()) :: __MODULE__.t()
  def cast(input = %{}) do
    res = %__MODULE__{
      amount: Map.get(input, :amount),
      from: Map.get(input, :from),
      spent?: Map.get(input, :spent),
      timestamp: Map.get(input, :timestamp)
    }

    case Map.get(input, :type) do
      :UCO ->
        %{res | type: :UCO}

      :token ->
        case Map.get(input, :token_address) do
          nil ->
            res

          token_address ->
            %{res | type: {:token, token_address, Map.get(input, :token_id)}}
        end

      :call ->
        %{res | type: :call}

      :state ->
        res
        |> Map.put(:type, :state)
        |> Map.put(:encoded_payload, Map.get(input, :encoded_payload))

      _ ->
        res
    end
  end

  @spec to_map(__MODULE__.t()) :: map()
  def to_map(%__MODULE__{
        amount: amount,
        from: from,
        spent?: spent?,
        type: :UCO,
        timestamp: timestamp
      }) do
    %{
      amount: amount,
      from: from,
      type: :UCO,
      spent: spent?,
      timestamp: timestamp
    }
  end

  def to_map(%__MODULE__{
        amount: amount,
        from: from,
        spent?: spent?,
        type: {:token, token_address, token_id},
        timestamp: timestamp
      }) do
    %{
      amount: amount,
      from: from,
      type: :token,
      token_address: token_address,
      token_id: token_id,
      spent: spent?,
      timestamp: timestamp
    }
  end

  def to_map(%__MODULE__{amount: _, from: from, spent?: spent?, type: :call, timestamp: timestamp}) do
    %{
      from: from,
      type: :call,
      spent: spent?,
      timestamp: timestamp
    }
  end

  def to_map(%__MODULE__{
        amount: _,
        from: from,
        spent?: spent?,
        type: :state,
        timestamp: timestamp,
        encoded_payload: encoded_payload
      }) do
    %{
      from: from,
      type: :state,
      spent: spent?,
      timestamp: timestamp,
      encoded_payload: encoded_payload |> State.deserialize() |> elem(0)
    }
  end
end
