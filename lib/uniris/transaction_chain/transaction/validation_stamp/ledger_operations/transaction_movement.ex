defmodule Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement do
  @moduledoc """
  Represents the ledger movements of the transaction extracted from
  the ledger or recipients part of the transaction and validated with the unspent outputs
  """
  defstruct [:to, :amount, :type]

  alias __MODULE__.Type
  alias Uniris.Crypto

  @typedoc """
  TransactionMovement is composed from:
  - to: receiver address of the movement
  - amount: specify the number assets to transfer to the recipients
  - type: asset type (ie. UCO or NFT)
  """
  @type t() :: %__MODULE__{
          to: Crypto.versioned_hash(),
          amount: float(),
          type: Type.t()
        }

  @doc """
  Serialize a transaction movement into binary format

  ## Examples

      iex> %TransactionMovement{
      ...>    to: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      ...>      159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
      ...>    amount: 0.30,
      ...>    type: :UCO
      ...>  }
      ...>  |> TransactionMovement.serialize()
      <<
      # Node public key
      0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
      # Amount
      63, 211, 51, 51, 51, 51, 51, 51,
      # UCO type
      0
      >>

      iex> %TransactionMovement{
      ...>    to: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      ...>      159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
      ...>    amount: 0.30,
      ...>    type: {:NFT, <<0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74, 
      ...>      197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>}
      ...>  }
      ...>  |> TransactionMovement.serialize()
      <<
      # Node public key
      0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
      # Amount
      63, 211, 51, 51, 51, 51, 51, 51,
      # NFT type
      1,
      # NFT address
      0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74, 
      197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175
      >>
  """
  @spec serialize(t()) :: <<_::64, _::_*8>>
  def serialize(%__MODULE__{to: to, amount: amount, type: type}) do
    <<to::binary, amount::float, Type.serialize(type)::binary>>
  end

  @doc """
  Deserialize an encoded transaction movement

  ## Examples

      iex> <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      ...> 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
      ...> 63, 211, 51, 51, 51, 51, 51, 51, 0
      ...> >>
      ...> |> TransactionMovement.deserialize()
      {
        %TransactionMovement{
          to: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
            159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
          amount: 0.30,
          type: :UCO
        },
        ""
      }

      iex> <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      ...> 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
      ...> 63, 211, 51, 51, 51, 51, 51, 51, 1, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
      ...> 197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175
      ...> >>
      ...> |> TransactionMovement.deserialize()
      {
        %TransactionMovement{
          to: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
            159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
          amount: 0.30,
          type: {:NFT, <<0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
                        197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>}
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<hash_id::8, rest::bitstring>>) do
    hash_size = Crypto.hash_size(hash_id)
    <<address::binary-size(hash_size), amount::float, rest::bitstring>> = rest
    {type, rest} = Type.deserialize(rest)

    {
      %__MODULE__{
        to: <<hash_id::8>> <> address,
        amount: amount,
        type: type
      },
      rest
    }
  end

  @spec from_map(map()) :: t()
  def from_map(movement = %{}) do
    res = %__MODULE__{
      to: Map.get(movement, :to),
      amount: Map.get(movement, :amount)
    }

    if Map.has_key?(movement, :type) do
      case Map.get(movement, :nft_address) do
        nil ->
          %{res | type: :UCO}

        nft_address ->
          %{res | type: {:NFT, nft_address}}
      end
    else
      res
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{to: to, amount: amount, type: :UCO}) do
    %{
      to: to,
      amount: amount,
      type: :UCO
    }
  end

  def to_map(%__MODULE__{to: to, amount: amount, type: {:NFT, nft_address}}) do
    %{
      to: to,
      amount: amount,
      type: :NFT,
      nft_address: nft_address
    }
  end
end
