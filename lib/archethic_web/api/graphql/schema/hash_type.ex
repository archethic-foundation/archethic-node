defmodule ArchethicWeb.API.GraphQL.Schema.HashType do
  @moduledoc false

  use Absinthe.Schema.Notation
  alias Archethic.Crypto

  @desc """
  The [Hash] scalar type represents a cryptographic hash used in
  the Archethic network with an identification byte to specify from which algorithm the hash was generated.
  The Hash appears in a JSON response as Base16 formatted string. The parsed hash will
  be converted to a binary and any invalid hash with an invalid algorithm or invalid size will be rejected
  """
  scalar :versioned_hash do
    serialize(&Base.encode16/1)
    parse(&parse_hash(&1, :versioned))
  end

  scalar :sha256_hash do
    serialize(&Base.encode16/1)
    parse(&parse_hash(&1, :sha256))
  end

  @spec parse_hash(Absinthe.Blueprint.Input.String.t(), hash_type :: :versioned | :sha256) ::
          {:ok, binary()} | :error
  defp parse_hash(%Absinthe.Blueprint.Input.String{value: hash}, hash_type) do
    with {:ok, hash} <- Base.decode16(hash, case: :mixed),
         true <- valid_hash?(hash, hash_type) do
      {:ok, hash}
    else
      _ -> :error
    end
  end

  defp parse_hash(_, _), do: :error

  defp valid_hash?(hash, :versioned), do: Crypto.valid_hash?(hash)
  defp valid_hash?(hash, :sha256), do: match?(<<_::binary-size(32)>>, hash)
end
