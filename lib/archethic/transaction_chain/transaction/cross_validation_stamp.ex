defmodule Archethic.TransactionChain.Transaction.CrossValidationStamp do
  @moduledoc """
  Represent a cross validation stamp validated a validation stamp.
  """

  defstruct [:node_public_key, :signature, inconsistencies: []]

  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.Utils

  @type inconsistency() ::
          :timestamp
          | :signature
          | :proof_of_work
          | :proof_of_integrity
          | :proof_of_election
          | :transaction_fee
          | :transaction_movements
          | :recipients
          | :unspent_outputs
          | :error
          | :protocol_version
          | :consumed_inputs
          | :aggregated_utxos

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
      validation_stamp
      |> get_row_data_to_sign(inconsistencies)
      |> Crypto.sign_with_mining_node_key()

    %__MODULE__{
      cross_stamp
      | node_public_key: Crypto.mining_node_public_key(),
        signature: signature
    }
  end

  @doc """
  returns raw data to sign
  """
  @spec get_row_data_to_sign(
          validation_stamp :: ValidationStamp.t(),
          inconsistencies :: list(inconsistency())
        ) :: binary()
  def get_row_data_to_sign(validation_stamp, inconsistencies) do
    raw_stamp = ValidationStamp.serialize(validation_stamp)
    Utils.wrap_binary([raw_stamp, marshal_inconsistencies(inconsistencies)])
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
    raw_stamp = ValidationStamp.serialize(stamp)

    data = [raw_stamp, marshal_inconsistencies(inconsistencies)]
    Crypto.verify?(signature, data, node_public_key)
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
      ...>   node_public_key:
      ...>     <<0, 0, 32, 44, 135, 146, 55, 226, 199, 234, 83, 141, 249, 46, 64, 213, 172, 218,
      ...>       137, 35, 16, 193, 228, 78, 130, 36, 204, 242, 96, 90, 230, 5, 193, 137>>,
      ...>   signature:
      ...>     <<70, 102, 163, 198, 192, 91, 177, 10, 201, 156, 10, 109, 165, 39, 226, 156, 72, 169,
      ...>       219, 71, 63, 236, 35, 228, 182, 45, 13, 166, 165, 102, 216, 23, 183, 46, 195, 74,
      ...>       85, 242, 164, 44, 225, 204, 233, 91, 217, 177, 243, 234, 229, 72, 149, 17, 40, 182,
      ...>       207, 127, 193, 3, 194, 156, 105, 209, 43, 161>>,
      ...>   inconsistencies: [:signature, :proof_of_work, :proof_of_integrity]
      ...> }
      ...> |> CrossValidationStamp.serialize()
      <<0, 0, 32, 44, 135, 146, 55, 226, 199, 234, 83, 141, 249, 46, 64, 213, 172, 218, 137, 35, 16,
        193, 228, 78, 130, 36, 204, 242, 96, 90, 230, 5, 193, 137, 64, 70, 102, 163, 198, 192, 91,
        177, 10, 201, 156, 10, 109, 165, 39, 226, 156, 72, 169, 219, 71, 63, 236, 35, 228, 182, 45,
        13, 166, 165, 102, 216, 23, 183, 46, 195, 74, 85, 242, 164, 44, 225, 204, 233, 91, 217, 177,
        243, 234, 229, 72, 149, 17, 40, 182, 207, 127, 193, 3, 194, 156, 105, 209, 43, 161, 3, 1, 2,
        3>>
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

  defp serialize_inconsistency(:timestamp), do: 0
  defp serialize_inconsistency(:signature), do: 1
  defp serialize_inconsistency(:proof_of_work), do: 2
  defp serialize_inconsistency(:proof_of_integrity), do: 3
  defp serialize_inconsistency(:proof_of_election), do: 4
  defp serialize_inconsistency(:transaction_fee), do: 5
  defp serialize_inconsistency(:transaction_movements), do: 6
  defp serialize_inconsistency(:unspent_outputs), do: 7
  defp serialize_inconsistency(:error), do: 8
  defp serialize_inconsistency(:protocol_version), do: 9
  defp serialize_inconsistency(:consumed_inputs), do: 10
  defp serialize_inconsistency(:aggregated_utxos), do: 11
  defp serialize_inconsistency(:recipients), do: 12

  @doc """
  Deserialize an encoded cross validation stamp

  ## Examples

      iex> <<0, 0, 32, 44, 135, 146, 55, 226, 199, 234, 83, 141, 249, 46, 64, 213, 172, 218, 137,
      ...>   35, 16, 193, 228, 78, 130, 36, 204, 242, 96, 90, 230, 5, 193, 137, 64, 70, 102, 163,
      ...>   198, 192, 91, 177, 10, 201, 156, 10, 109, 165, 39, 226, 156, 72, 169, 219, 71, 63, 236,
      ...>   35, 228, 182, 45, 13, 166, 165, 102, 216, 23, 183, 46, 195, 74, 85, 242, 164, 44, 225,
      ...>   204, 233, 91, 217, 177, 243, 234, 229, 72, 149, 17, 40, 182, 207, 127, 193, 3, 194,
      ...>   156, 105, 209, 43, 161, 3, 1, 2, 3>>
      ...> |> CrossValidationStamp.deserialize()
      {
        %CrossValidationStamp{
          node_public_key:
            <<0, 0, 32, 44, 135, 146, 55, 226, 199, 234, 83, 141, 249, 46, 64, 213, 172, 218, 137,
              35, 16, 193, 228, 78, 130, 36, 204, 242, 96, 90, 230, 5, 193, 137>>,
          signature:
            <<70, 102, 163, 198, 192, 91, 177, 10, 201, 156, 10, 109, 165, 39, 226, 156, 72, 169,
              219, 71, 63, 236, 35, 228, 182, 45, 13, 166, 165, 102, 216, 23, 183, 46, 195, 74, 85,
              242, 164, 44, 225, 204, 233, 91, 217, 177, 243, 234, 229, 72, 149, 17, 40, 182, 207,
              127, 193, 3, 194, 156, 105, 209, 43, 161>>,
          inconsistencies: [:signature, :proof_of_work, :proof_of_integrity]
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(data) do
    {public_key,
     <<signature_size::8, signature::binary-size(signature_size), nb_inconsistencies::8,
       rest::bitstring>>} = Utils.deserialize_public_key(data)

    {inconsistencies, rest} = reduce_inconsistencies(rest, nb_inconsistencies, [])

    {
      %__MODULE__{
        node_public_key: public_key,
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

  defp do_reduce_inconsistencies(<<0::8, rest::bitstring>>), do: {:timestamp, rest}
  defp do_reduce_inconsistencies(<<1::8, rest::bitstring>>), do: {:signature, rest}
  defp do_reduce_inconsistencies(<<2::8, rest::bitstring>>), do: {:proof_of_work, rest}
  defp do_reduce_inconsistencies(<<3::8, rest::bitstring>>), do: {:proof_of_integrity, rest}
  defp do_reduce_inconsistencies(<<4::8, rest::bitstring>>), do: {:proof_of_election, rest}
  defp do_reduce_inconsistencies(<<5::8, rest::bitstring>>), do: {:transaction_fee, rest}
  defp do_reduce_inconsistencies(<<6::8, rest::bitstring>>), do: {:transaction_movements, rest}
  defp do_reduce_inconsistencies(<<7::8, rest::bitstring>>), do: {:unspent_outputs, rest}
  defp do_reduce_inconsistencies(<<8::8, rest::bitstring>>), do: {:error, rest}
  defp do_reduce_inconsistencies(<<9::8, rest::bitstring>>), do: {:protocol_version, rest}
  defp do_reduce_inconsistencies(<<10::8, rest::bitstring>>), do: {:consumed_inputs, rest}
  defp do_reduce_inconsistencies(<<11::8, rest::bitstring>>), do: {:aggregated_utxos, rest}
  defp do_reduce_inconsistencies(<<12::8, rest::bitstring>>), do: {:recipients, rest}

  @spec cast(map()) :: t()
  def cast(stamp = %{}) do
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
