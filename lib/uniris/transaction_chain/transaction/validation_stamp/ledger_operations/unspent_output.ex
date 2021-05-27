defmodule Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput do
  @moduledoc """
  Represents an unspent output from a transaction.
  """
  defstruct [:amount, :from, :type, :timestamp, reward?: false]

  alias Uniris.Crypto

  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement.Type,
    as: TransactionMovementType

  @type t :: %__MODULE__{
          amount: float(),
          from: Crypto.versioned_hash(),
          type: TransactionMovementType.t(),
          reward?: boolean()
        }

  @doc """
  Serialize unspent output into binary format

  ## Examples

   With UCO movements:

      iex> %UnspentOutput{
      ...>    from: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      ...>      159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
      ...>    amount: 10.5,
      ...>    type: :UCO
      ...>  }
      ...>  |> UnspentOutput.serialize()
      <<
      # From
      0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
      # Amount
      64, 37, 0, 0, 0, 0, 0, 0,
      # UCO Unspent Output
      0,
      # Reward?
      0
      >>

  With NFT movements:

      iex> %UnspentOutput{
      ...>    from: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      ...>      159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
      ...>    amount: 10.5,
      ...>    type: {:NFT, <<0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
      ...>      197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>}
      ...>  }
      ...>  |> UnspentOutput.serialize()
      <<
      # From
      0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
      # Amount
      64, 37, 0, 0, 0, 0, 0, 0,
      # NFT Unspent Output
      1,
      # NFT address
      0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
      197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175, 
      # Reward?
      0
      >>
  """
  @spec serialize(__MODULE__.t()) :: <<_::64, _::_*8>>
  def serialize(%__MODULE__{from: from, amount: amount, type: type, reward?: reward?}) do
    reward_bit = if reward?, do: 1, else: 0

    <<from::binary, amount::float, TransactionMovementType.serialize(type)::binary,
      reward_bit::8>>
  end

  @doc """
  Deserialize an encoded unspent output

  ## Examples

      iex> <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      ...> 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
      ...> 64, 37, 0, 0, 0, 0, 0, 0, 0, 0
      ...> >>
      ...> |> UnspentOutput.deserialize()
      {
        %UnspentOutput{
          from: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
            159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
          amount: 10.5,
          type: :UCO,
          reward?: false
        },
        ""
      }

      iex> <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      ...> 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
      ...> 64, 37, 0, 0, 0, 0, 0, 0, 1, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
      ...> 197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175, 0
      ...> >>
      ...> |> UnspentOutput.deserialize()
      {
        %UnspentOutput{
          from: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
            159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
          amount: 10.5,
          type: {:NFT, <<0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
            197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>},
          reward?: false
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {__MODULE__.t(), bitstring}
  def deserialize(<<hash_id::8, rest::bitstring>>) do
    hash_size = Crypto.hash_size(hash_id)
    <<address::binary-size(hash_size), amount::float, rest::bitstring>> = rest
    {type, <<reward_bit::8, rest::bitstring>>} = TransactionMovementType.deserialize(rest)

    reward? = if reward_bit == 1, do: true, else: false

    {
      %__MODULE__{
        from: <<hash_id::8>> <> address,
        amount: amount,
        type: type,
        reward?: reward?
      },
      rest
    }
  end

  @spec from_map(map()) :: __MODULE__.t()
  def from_map(unspent_output = %{}) do
    res = %__MODULE__{
      from: Map.get(unspent_output, :from),
      amount: Map.get(unspent_output, :amount),
      reward?: Map.get(unspent_output, :reward)
    }

    case Map.get(unspent_output, :type) do
      "NFT" ->
        %{res | type: {:NFT, Map.get(unspent_output, :nft_address)}}

      _ ->
        %{res | type: :UCO}
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{from: from, amount: amount, type: :UCO, reward?: reward?}) do
    %{
      from: from,
      amount: amount,
      type: "UCO",
      reward: reward?
    }
  end

  def to_map(%__MODULE__{from: from, amount: amount, type: {:NFT, nft_address}}) do
    %{
      from: from,
      amount: amount,
      type: "NFT",
      nft_address: nft_address,
      reward: false
    }
  end
end
