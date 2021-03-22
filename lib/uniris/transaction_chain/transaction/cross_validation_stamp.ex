defmodule Uniris.TransactionChain.Transaction.CrossValidationStamp do
  @moduledoc """
  Represent a cross validation stamp validated a validation stamp.
  """

  defstruct [:node_public_key, :signature, inconsistencies: []]

  alias Uniris.Crypto
  alias Uniris.TransactionChain.Transaction.ValidationStamp

  @type inconsistency() ::
          :signature
          | :proof_of_work
          | :proof_of_integrity
          | :transaction_fee
          | :transaction_movements
          | :unspent_outputs
          | :node_movements
          | :errors

  @typedoc """
  A cross validation stamp is composed from:
  - Public key: identity of the node signer
  - Signature: built from the validation stamp and the inconsistencies found
  - Inconsistencies: a list of errors from the validation stamp
  """
  @type t :: %__MODULE__{
          node_public_key: nil | Crypto.key(),
          signature: nil | binary(),
          inconsistencies: list(inconsistency())
        }

  @doc """
  Sign the cross validation stamp using the validation stamp and inconsistencies list
  """
  @spec sign(t(), ValidationStamp.t()) :: t()
  def sign(
        cross_stamp = %__MODULE__{inconsistencies: inconsistencies},
        validation_stamp = %ValidationStamp{}
      ) do
    signature =
      [ValidationStamp.serialize(validation_stamp), marshal_inconsistencies(inconsistencies)]
      |> Crypto.sign_with_node_key()

    %{cross_stamp | node_public_key: Crypto.node_public_key(), signature: signature}
  end

  @doc """
  Determines if the cross validation stamp signature valid from a validation stamp
  """
  @spec valid_signature?(
          t(),
          ValidationStamp.t()
        ) :: boolean()
  def valid_signature?(
        %__MODULE__{
          signature: signature,
          inconsistencies: inconsistencies,
          node_public_key: node_public_key
        },
        stamp = %ValidationStamp{}
      ) do
    data = [ValidationStamp.serialize(stamp), marshal_inconsistencies(inconsistencies)]
    Crypto.verify(signature, data, node_public_key)
  end

  defp marshal_inconsistencies(inconsistencies) do
    inconsistencies
    |> Enum.map(&serialize_inconsistency/1)
    |> :erlang.list_to_binary()
  end

  @doc """
  Serialize a cross validation stamp into binary format

  ## Examples

      iex> %CrossValidationStamp{
      ...>   node_public_key: <<0, 32, 44, 135, 146, 55, 226, 199, 234, 83, 141, 249, 46, 64, 213, 172, 218, 137,
      ...>     35, 16, 193, 228, 78, 130, 36, 204, 242, 96, 90, 230, 5, 193, 137>>,
      ...>   signature: <<70, 102, 163, 198, 192, 91, 177, 10, 201, 156, 10, 109, 165, 39, 226, 156, 72,
      ...>     169, 219, 71, 63, 236, 35, 228, 182, 45, 13, 166, 165, 102, 216, 23, 183, 46,
      ...>     195, 74, 85, 242, 164, 44, 225, 204, 233, 91, 217, 177, 243, 234, 229, 72,
      ...>    149, 17, 40, 182, 207, 127, 193, 3, 194, 156, 105, 209, 43, 161>>,
      ...>   inconsistencies: [:signature, :proof_of_work, :proof_of_integrity]
      ...> }
      ...> |> CrossValidationStamp.serialize()
      <<
      # Public key
      0, 32, 44, 135, 146, 55, 226, 199, 234, 83, 141, 249, 46, 64, 213, 172, 218, 137,
      35, 16, 193, 228, 78, 130, 36, 204, 242, 96, 90, 230, 5, 193, 137,
      # Signature size
      64,
      # Signature
      70, 102, 163, 198, 192, 91, 177, 10, 201, 156, 10, 109, 165, 39, 226, 156, 72,
      169, 219, 71, 63, 236, 35, 228, 182, 45, 13, 166, 165, 102, 216, 23, 183, 46,
      195, 74, 85, 242, 164, 44, 225, 204, 233, 91, 217, 177, 243, 234, 229, 72,
      149, 17, 40, 182, 207, 127, 193, 3, 194, 156, 105, 209, 43, 161,
      # Number of inconsistencies
      3,
      # Inconsistencies
      0, 1, 2
      >>
  """
  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{
        node_public_key: node_public_key,
        signature: signature,
        inconsistencies: inconsistencies
      }) do
    inconsistencies_bin =
      inconsistencies
      |> Enum.map(&serialize_inconsistency(&1))
      |> :erlang.list_to_binary()

    <<node_public_key::binary, byte_size(signature)::8, signature::binary,
      length(inconsistencies)::8, inconsistencies_bin::binary>>
  end

  defp serialize_inconsistency(:signature), do: 0
  defp serialize_inconsistency(:proof_of_work), do: 1
  defp serialize_inconsistency(:proof_of_integrity), do: 2
  defp serialize_inconsistency(:transaction_fee), do: 3
  defp serialize_inconsistency(:transaction_movements), do: 4
  defp serialize_inconsistency(:unspent_outputs), do: 5
  defp serialize_inconsistency(:node_movements), do: 6
  defp serialize_inconsistency(:errors), do: 7

  @doc """
  Deserialize an encoded cross validation stamp

  ## Examples

      iex> <<0, 32, 44, 135, 146, 55, 226, 199, 234, 83, 141, 249, 46, 64, 213, 172, 218, 137,
      ...> 35, 16, 193, 228, 78, 130, 36, 204, 242, 96, 90, 230, 5, 193, 137,
      ...> 64, 70, 102, 163, 198, 192, 91, 177, 10, 201, 156, 10, 109, 165, 39, 226, 156, 72,
      ...> 169, 219, 71, 63, 236, 35, 228, 182, 45, 13, 166, 165, 102, 216, 23, 183, 46,
      ...> 195, 74, 85, 242, 164, 44, 225, 204, 233, 91, 217, 177, 243, 234, 229, 72,
      ...> 149, 17, 40, 182, 207, 127, 193, 3, 194, 156, 105, 209, 43, 161,
      ...> 3, 0, 1, 2>>
      ...> |> CrossValidationStamp.deserialize()
      {
        %CrossValidationStamp{
          node_public_key:  <<0, 32, 44, 135, 146, 55, 226, 199, 234, 83, 141, 249, 46, 64, 213, 172, 218, 137,
            35, 16, 193, 228, 78, 130, 36, 204, 242, 96, 90, 230, 5, 193, 137>>,
          signature: <<70, 102, 163, 198, 192, 91, 177, 10, 201, 156, 10, 109, 165, 39, 226, 156, 72,
            169, 219, 71, 63, 236, 35, 228, 182, 45, 13, 166, 165, 102, 216, 23, 183, 46,
            195, 74, 85, 242, 164, 44, 225, 204, 233, 91, 217, 177, 243, 234, 229, 72,
            149, 17, 40, 182, 207, 127, 193, 3, 194, 156, 105, 209, 43, 161>>,
          inconsistencies: [:signature, :proof_of_work, :proof_of_integrity]
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<curve_id::8, rest::bitstring>>) do
    key_size = Crypto.key_size(curve_id)

    <<key::binary-size(key_size), signature_size::8, signature::binary-size(signature_size),
      nb_inconsistencies::8, rest::bitstring>> = rest

    {inconsistencies, rest} = reduce_inconsistencies(rest, nb_inconsistencies, [])

    {
      %__MODULE__{
        node_public_key: <<curve_id::8>> <> key,
        signature: signature,
        inconsistencies: inconsistencies
      },
      rest
    }
  end

  defp reduce_inconsistencies(rest, nb_inconsistencies, acc)
       when nb_inconsistencies == length(acc) do
    {Enum.reverse(acc), rest}
  end

  defp reduce_inconsistencies(rest, nb_inconsistencies, acc) do
    {inconsistency, rest} = do_reduce_inconsistencies(rest)
    reduce_inconsistencies(rest, nb_inconsistencies, [inconsistency | acc])
  end

  defp do_reduce_inconsistencies(<<0::8, rest::bitstring>>), do: {:signature, rest}
  defp do_reduce_inconsistencies(<<1::8, rest::bitstring>>), do: {:proof_of_work, rest}
  defp do_reduce_inconsistencies(<<2::8, rest::bitstring>>), do: {:proof_of_integrity, rest}
  defp do_reduce_inconsistencies(<<3::8, rest::bitstring>>), do: {:transaction_fee, rest}
  defp do_reduce_inconsistencies(<<4::8, rest::bitstring>>), do: {:transaction_movement, rest}
  defp do_reduce_inconsistencies(<<5::8, rest::bitstring>>), do: {:unspent_outputs, rest}
  defp do_reduce_inconsistencies(<<6::8, rest::bitstring>>), do: {:node_movements, rest}
  defp do_reduce_inconsistencies(<<7::8, rest::bitstring>>), do: {:errors, rest}

  @spec from_map(map()) :: t()
  def from_map(stamp = %{}) do
    %__MODULE__{
      node_public_key: Map.get(stamp, :node_public_key),
      signature: Map.get(stamp, :signature),
      inconsistencies: []
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{signature: signature, node_public_key: public_key}) do
    %{
      node_public_key: public_key,
      signature: signature,
      inconsistencies: []
    }
  end
end
