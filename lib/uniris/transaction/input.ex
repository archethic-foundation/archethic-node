defmodule Uniris.TransactionInput do
  @moduledoc """
  Represents an input from a transaction either spent or unspent
  """
  defstruct [:from, :amount, :spent?]

  alias Uniris.Crypto

  @type t() :: %__MODULE__{
          from: Crypto.versioned_hash(),
          amount: float(),
          spent?: boolean()
        }

  @doc """
  Serialize a transaction input into binary

  ## Examples

      iex> %Uniris.TransactionInput{
      ...>    from:  <<0, 53, 130, 31, 59, 131, 78, 78, 34, 179, 66, 2, 120, 117, 4, 119, 81, 111, 187,
      ...>       166, 83, 194, 42, 253, 99, 189, 24, 68, 40, 178, 142, 163, 56>>,
      ...>    amount: 10.5,
      ...>    spent?: true
      ...> }
      ...> |> Uniris.TransactionInput.serialize()
      <<
      # From
      0, 53, 130, 31, 59, 131, 78, 78, 34, 179, 66, 2, 120, 117, 4, 119, 81, 111, 187,
      166, 83, 194, 42, 253, 99, 189, 24, 68, 40, 178, 142, 163, 56,
      # Amount
      64, 37, 0, 0, 0, 0, 0, 0,
      # Spent
      1::1
      >>
  """
  @spec serialize(__MODULE__.t()) :: bitstring()
  def serialize(%__MODULE__{from: from, amount: amount, spent?: true}) do
    <<from::binary, amount::float, 1::1>>
  end

  def serialize(%__MODULE__{from: from, amount: amount, spent?: _}) do
    <<from::binary, amount::float, 0::1>>
  end

  @doc """
  Deserialize an encoded TransactionInput

  ## Examples

      iex> %Uniris.TransactionInput{
      ...>    from:  <<0, 53, 130, 31, 59, 131, 78, 78, 34, 179, 66, 2, 120, 117, 4, 119, 81, 111, 187,
      ...>       166, 83, 194, 42, 253, 99, 189, 24, 68, 40, 178, 142, 163, 56>>,
      ...>    amount: 10.5,
      ...>    spent?: true
      ...> }
      ...> |> Uniris.TransactionInput.serialize()
      ...> |> Uniris.TransactionInput.deserialize()
      {
        %Uniris.TransactionInput{
          from:  <<0, 53, 130, 31, 59, 131, 78, 78, 34, 179, 66, 2, 120, 117, 4, 119, 81, 111, 187,
            166, 83, 194, 42, 253, 99, 189, 24, 68, 40, 178, 142, 163, 56>>,
          amount: 10.5,
          spent?: true
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {__MODULE__.t(), bitstring()}
  def deserialize(<<hash_id::8, rest::bitstring>>) do
    hash_size = Crypto.hash_size(hash_id)
    <<from::binary-size(hash_size), amount::float, spent?::1, rest::bitstring>> = rest

    case spent? do
      0 ->
        {
          %__MODULE__{
            from: <<hash_id::8, from::binary>>,
            amount: amount,
            spent?: false
          },
          rest
        }

      1 ->
        {
          %__MODULE__{
            from: <<hash_id::8, from::binary>>,
            amount: amount,
            spent?: true
          },
          rest
        }
    end
  end

  @spec from_map(map()) :: __MODULE__.t()
  def from_map(input = %{}) do
    %__MODULE__{
      amount: Map.get(input, :amount),
      from: Map.get(input, :from),
      spent?: Map.get(input, :spent?)
    }
  end

  @spec to_map(__MODULE__.t()) :: map()
  def to_map(%__MODULE__{amount: amount, from: from, spent?: spent?}) do
    %{
      amount: amount,
      from: from,
      spent?: spent?
    }
  end
end
