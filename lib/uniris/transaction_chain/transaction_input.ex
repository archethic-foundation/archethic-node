defmodule Uniris.TransactionChain.TransactionInput do
  @moduledoc """
  Represents an transaction sent to an account either spent or unspent
  """
  defstruct [:from, :amount, :type, :timestamp, spent?: false]

  alias Uniris.Crypto

  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement.Type,
    as: TransactionMovementType

  @type t() :: %__MODULE__{
          from: Crypto.versioned_hash(),
          amount: float(),
          spent?: boolean(),
          type: TransactionMovementType.t() | :call,
          timestamp: DateTime.t()
        }

  @doc """
  Serialize an account input into binary

  ## Examples

      iex> %TransactionInput{
      ...>    from:  <<0, 53, 130, 31, 59, 131, 78, 78, 34, 179, 66, 2, 120, 117, 4, 119, 81, 111, 187,
      ...>       166, 83, 194, 42, 253, 99, 189, 24, 68, 40, 178, 142, 163, 56>>,
      ...>    amount: 10.5,
      ...>    type: :UCO,
      ...>    spent?: true,
      ...>    timestamp: ~U[2021-03-05 11:17:20Z]
      ...> }
      ...> |> TransactionInput.serialize()
      <<
      # From
      0, 53, 130, 31, 59, 131, 78, 78, 34, 179, 66, 2, 120, 117, 4, 119, 81, 111, 187,
      166, 83, 194, 42, 253, 99, 189, 24, 68, 40, 178, 142, 163, 56,
      # Type
      1::1,
      # Spent
      1::1,
      # Amount
      64, 37, 0, 0, 0, 0, 0, 0,
      # Input type (UCO)
      0,
      # timestamp
      96, 66, 19, 64
      >>
  """
  @spec serialize(__MODULE__.t()) :: bitstring()
  def serialize(%__MODULE__{
        from: from,
        amount: amount,
        type: type,
        spent?: spent?,
        timestamp: timestamp
      }) do
    case type do
      :call ->
        <<from::binary, 0::1, 0::1, DateTime.to_unix(timestamp)::32>>

      type ->
        spend_bit = if spent?, do: 1, else: 0

        <<from::binary, 1::1, spend_bit::1, amount::float,
          TransactionMovementType.serialize(type)::binary, DateTime.to_unix(timestamp)::32>>
    end
  end

  @doc """
  Deserialize an encoded TransactionInput

  ## Examples

      iex>  <<0, 53, 130, 31, 59, 131, 78, 78, 34, 179, 66, 2, 120, 117, 4, 119, 81, 111, 187,
      ...>  166, 83, 194, 42, 253, 99, 189, 24, 68, 40, 178, 142, 163, 56,
      ...>  1::1, 1::1,
      ...>  64, 37, 0, 0, 0, 0, 0, 0,
      ...>  0,
      ...>  96, 66, 19, 64>>
      ...> |> TransactionInput.deserialize()
      {
        %TransactionInput{
          from:  <<0, 53, 130, 31, 59, 131, 78, 78, 34, 179, 66, 2, 120, 117, 4, 119, 81, 111, 187,
            166, 83, 194, 42, 253, 99, 189, 24, 68, 40, 178, 142, 163, 56>>,
          amount: 10.5,
          type: :UCO,
          spent?: true,
          timestamp: ~U[2021-03-05 11:17:20Z]
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {__MODULE__.t(), bitstring()}
  def deserialize(<<hash_id::8, rest::bitstring>>) do
    hash_size = Crypto.hash_size(hash_id)
    <<from::binary-size(hash_size), type_bit::1, spent_bit::1, rest::bitstring>> = rest
    spent? = if spent_bit == 1, do: true, else: false

    case type_bit do
      0 ->
        <<timestamp::32, rest::bitstring>> = rest

        {
          %__MODULE__{
            from: <<hash_id::8, from::binary>>,
            spent?: spent?,
            type: :call,
            timestamp: DateTime.from_unix!(timestamp)
          },
          rest
        }

      1 ->
        <<amount::float, rest::bitstring>> = rest

        {movement_type, <<timestamp::32, rest::bitstring>>} =
          TransactionMovementType.deserialize(rest)

        {
          %__MODULE__{
            from: <<hash_id::8, from::binary>>,
            spent?: spent?,
            amount: amount,
            type: movement_type,
            timestamp: DateTime.from_unix!(timestamp)
          },
          rest
        }
    end
  end

  @spec from_map(map()) :: __MODULE__.t()
  def from_map(input = %{}) do
    res = %__MODULE__{
      amount: Map.get(input, :amount),
      from: Map.get(input, :from),
      spent?: Map.get(input, :spent?),
      timestamp: Map.get(input, :timestamp)
    }

    case Map.get(input, :type) do
      :UCO ->
        %{res | type: :UCO}

      :NFT ->
        case Map.get(input, :nft_address) do
          nil ->
            res

          nft_address ->
            %{res | type: {:NFT, nft_address}}
        end

      :call ->
        %{res | type: :call}

      nil ->
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
      spent?: spent?,
      timestamp: timestamp
    }
  end

  def to_map(%__MODULE__{
        amount: amount,
        from: from,
        spent?: spent?,
        type: {:NFT, nft_address},
        timestamp: timestamp
      }) do
    %{
      amount: amount,
      from: from,
      type: :NFT,
      nft_address: nft_address,
      spent?: spent?,
      timestamp: timestamp
    }
  end

  def to_map(%__MODULE__{amount: _, from: from, spent?: spent?, type: :call, timestamp: timestamp}) do
    %{
      from: from,
      type: :call,
      spent?: spent?,
      timestamp: timestamp
    }
  end
end
