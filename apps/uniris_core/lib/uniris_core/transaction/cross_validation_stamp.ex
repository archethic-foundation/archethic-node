defmodule UnirisCore.Transaction.CrossValidationStamp do
  @moduledoc """
  Represent a cross validation stamp validated a validation stamp.

  """

  defstruct [:node_public_key, :signature, :inconsistencies]

  alias UnirisCore.Crypto
  alias UnirisCore.Transaction.ValidationStamp

  @typedoc """
  Any cross validation stamp is composed by:
  - Public key: identity of the node
  - Signature: built from the validation stamp if no inconsistencies or from the list of inconsistencies otherwise
  - Inconsistencies: a list of errors found by a `ValidationStamp.verify/6`
  """
  @type t :: %__MODULE__{
          node_public_key: Crypto.key(),
          signature: binary(),
          inconsistencies: list(ValidationStamp.inconsistency())
        }

  @doc """
  Perform a signature of the validation if valid otherwise on the inconsistencies found
  """
  @spec new(ValidationStamp.t(), inconsistencies :: list()) :: __MODULE__.t()
  def new(stamp = %ValidationStamp{}, []) do
    raw_stamp = ValidationStamp.serialize(stamp)

    %__MODULE__{
      node_public_key: Crypto.node_public_key(),
      signature: Crypto.sign_with_node_key(raw_stamp),
      inconsistencies: []
    }
  end

  def new(%ValidationStamp{}, inconsistencies) when is_list(inconsistencies) do
    raw_inconsistencies =
      inconsistencies
      |> Enum.map(&serialize_inconsistency/1)
      |> :erlang.list_to_binary()

    %__MODULE__{
      node_public_key: Crypto.node_public_key(),
      signature: Crypto.sign_with_node_key(raw_inconsistencies),
      inconsistencies: inconsistencies
    }
  end

  @doc """
  Determines if a cross validation stamp is valid.

  According to the presence of inconsistencies, those are verified against the signature,
  otherwise the signature is verified with the validation stamp
  """
  @spec valid?(
          __MODULE__.t(),
          ValidationStamp.t()
        ) :: boolean()
  def valid?(
        %__MODULE__{signature: signature, inconsistencies: [], node_public_key: node_public_key},
        stamp = %ValidationStamp{}
      ) do
    raw_stamp = ValidationStamp.serialize(stamp)
    Crypto.verify(signature, raw_stamp, node_public_key)
  end

  def valid?(
        %__MODULE__{
          signature: signature,
          inconsistencies: inconsistencies,
          node_public_key: node_public_key
        },
        _stamp = %ValidationStamp{}
      ) do
    raw_inconsistencies =
      inconsistencies
      |> Enum.map(&serialize_inconsistency/1)
      |> :erlang.list_to_binary()

    Crypto.verify(signature, raw_inconsistencies, node_public_key)
  end

  @doc """
  Serialize a cross validation stamp into binary format

  ## Examples

      iex> UnirisCore.Transaction.CrossValidationStamp.serialize(%UnirisCore.Transaction.CrossValidationStamp{
      ...>   node_public_key: <<0, 32, 44, 135, 146, 55, 226, 199, 234, 83, 141, 249, 46, 64, 213, 172, 218, 137,
      ...>     35, 16, 193, 228, 78, 130, 36, 204, 242, 96, 90, 230, 5, 193, 137>>,
      ...>   signature: <<70, 102, 163, 198, 192, 91, 177, 10, 201, 156, 10, 109, 165, 39, 226, 156, 72,
      ...>     169, 219, 71, 63, 236, 35, 228, 182, 45, 13, 166, 165, 102, 216, 23, 183, 46,
      ...>     195, 74, 85, 242, 164, 44, 225, 204, 233, 91, 217, 177, 243, 234, 229, 72,
      ...>    149, 17, 40, 182, 207, 127, 193, 3, 194, 156, 105, 209, 43, 161>>,
      ...>   inconsistencies: [:signature, :proof_of_work, :proof_of_integrity]
      ...> })
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
  @spec serialize(__MODULE__.t()) :: binary()
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
  defp serialize_inconsistency(:ledger_operations), do: 3

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
      ...> |> UnirisCore.Transaction.CrossValidationStamp.deserialize()
      {
        %UnirisCore.Transaction.CrossValidationStamp{
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
  @spec deserialize(bitstring()) :: {__MODULE__.t(), bitstring()}
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
  defp do_reduce_inconsistencies(<<3::8, rest::bitstring>>), do: {:ledger_operations, rest}
end
