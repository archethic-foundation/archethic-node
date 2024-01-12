defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement do
  @moduledoc """
  Represents the ledger movements of the transaction extracted from
  the ledger or recipients part of the transaction and validated with the unspent outputs
  """
  defstruct [:to, :amount, :type]

  alias __MODULE__.Type
  alias Archethic.Crypto
  alias Archethic.Reward
  alias Archethic.TransactionChain.Transaction
  alias Archethic.Utils

  @typedoc """
  TransactionMovement is composed from:
  - to: receiver address of the movement
  - amount: specify the number assets to transfer to the recipients (smallest unit of uco 10^-8)
  - type: asset type (ie. UCO or Token)
  """
  @type t() :: %__MODULE__{
          to: Crypto.versioned_hash(),
          amount: non_neg_integer(),
          type: Type.t()
        }

  @doc """
  Serialize a transaction movement into binary format

  ## Examples

    iex> %TransactionMovement{
    ...>    to: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
    ...>      159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
    ...>    amount: 30_000_000,
    ...>    type: :UCO
    ...>  }
    ...>  |> TransactionMovement.serialize(current_protocol_version())
    <<
    # Node public key
    0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
    159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
    # Amount
    0, 0, 0, 0, 1, 201, 195, 128,
    # UCO type
    0>>

    iex> %TransactionMovement{
    ...>    to: <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
    ...>      159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
    ...>    amount: 30_000_000,
    ...>    type: {:token, <<0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
    ...>      197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>, 0}
    ...> }
    ...> |> TransactionMovement.serialize(current_protocol_version())
    <<
    # Node public key
    0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
    159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
    # Amount
    0, 0, 0, 0, 1, 201, 195, 128,
    # Token type
    1,
    # Token address
    0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
    197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175,
    # Token ID
    1, 0
    >>
  """
  @spec serialize(tx_movement :: t(), protocol_version :: non_neg_integer()) :: bitstring()
  def serialize(%__MODULE__{to: to, amount: amount, type: type}, _protocol_version) do
    <<to::binary, amount::64, Type.serialize(type)::binary>>
  end

  @doc """
  Deserialize an encoded transaction movement

  ## Examples

    iex> <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
    ...> 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
    ...> 0, 0, 0, 0, 1, 201, 195, 128, 0>>
    ...> |> TransactionMovement.deserialize(current_protocol_version())
    {
      %TransactionMovement{
        to: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
          159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        amount: 30_000_000,
        type: :UCO
      },
      ""
    }

    iex> <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
    ...> 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
    ...> 0, 0, 0, 0, 1, 201, 195, 128, 1, 0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
    ...> 197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175, 1, 0
    ...> >>
    ...> |> TransactionMovement.deserialize(current_protocol_version())
    {
      %TransactionMovement{
        to: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
          159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        amount: 30_000_000,
        type: {:token, <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
                      197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>, 0}
      },
      ""
    }
  """
  @spec deserialize(data :: bitstring(), protocol_version :: non_neg_integer()) ::
          {t(), bitstring}
  def deserialize(data, _protocol_version) when is_bitstring(data) do
    {address, <<amount::64, rest::bitstring>>} = Utils.deserialize_address(data)
    {type, rest} = Type.deserialize(rest)

    {
      %__MODULE__{
        to: address,
        amount: amount,
        type: type
      },
      rest
    }
  end

  @doc """
  Convert a map to TransactionMovement Struct

  ## Examples

    iex> %{
    ...>   to: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194, 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
    ...>   amount: 30_000_000,
    ...>   type: :UCO
    ...> }
    ...> |> TransactionMovement.cast()
    %TransactionMovement{
      to: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194, 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
      amount: 30_000_000,
      type: :UCO
    }

    iex> %{
    ...>    to: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68,
    ...>      194,159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
    ...>    amount: 30_000_000,
    ...>    type: {:token, <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71,
    ...>      140, 74, 197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>, 0}
    ...>  }
    ...>  |> TransactionMovement.cast()
    %TransactionMovement{
      to: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
       159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
      amount: 30_000_000,
      type: {:token, <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71,
       140, 74, 197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>, 0}
    }

  """
  @spec cast(map()) :: t()
  def cast(movement = %{}) do
    %__MODULE__{
      to: Map.get(movement, :to),
      amount: Map.get(movement, :amount),
      type: Map.get(movement, :type)
    }
  end

  @doc """
  Convert TransactionMovement Struct to a Map

  ## Examples

    iex> %TransactionMovement{
    ...>   to: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194, 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
    ...>   amount: 30_000_000,
    ...>   type: :UCO
    ...> }
    ...> |> TransactionMovement.to_map()
    %{
      to: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194, 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
      amount: 30_000_000,
      type: "UCO"
     }

    iex> %TransactionMovement{
    ...>   to: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194, 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
    ...>   amount: 30_000_000,
    ...>   type: {:token, <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74, 197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>, 0}
    ...> }
    ...> |> TransactionMovement.to_map()
    %{
      to: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194, 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
      amount: 30_000_000,
      type:  "token",
      token_address: <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74, 197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
      token_id: 0
    }

  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{to: to, amount: amount, type: :UCO}) do
    %{
      to: to,
      amount: amount,
      type: "UCO"
    }
  end

  def to_map(%__MODULE__{
        to: to,
        amount: amount,
        type: {:token, token_address, token_id}
      }) do
    %{
      to: to,
      amount: amount,
      type: "token",
      token_address: token_address,
      token_id: token_id
    }
  end

  @doc """
  Resolve the addresses of given movements
  If a movement does not have a resolved address, it is dropped
  """
  @spec resolve_addresses(list(t()), %{Crypto.prepended_hash() => Crypto.prepended_hash()}) ::
          list(t())
  def resolve_addresses(movements, resolved_addresses) do
    movements
    |> Enum.reduce([], fn mvt = %__MODULE__{to: to}, acc ->
      case Map.get(resolved_addresses, to) do
        nil -> acc
        resolved_address -> [%__MODULE__{mvt | to: resolved_address} | acc]
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Convert reward token movement to UCO movement
  """
  @spec maybe_convert_reward(movement :: t(), tx_type :: Transaction.transaction_type()) ::
          t()
  def maybe_convert_reward(
        movement = %__MODULE__{type: {:token, token_address, _token_id}},
        tx_type
      )
      when tx_type != :node_rewards do
    if Reward.is_reward_token?(token_address),
      do: %__MODULE__{movement | type: :UCO},
      else: movement
  end

  def maybe_convert_reward(movement, _), do: movement

  @doc """
  Aggreggate movement by type and recipient address
  """
  @spec aggregate(list(t())) :: list(t())
  def aggregate(movements) do
    Enum.reduce(
      movements,
      %{},
      fn movement = %__MODULE__{to: to, type: type, amount: amount}, acc ->
        Map.update(acc, {to, type}, movement, &%__MODULE__{&1 | amount: &1.amount + amount})
      end
    )
    |> Map.values()
  end
end
