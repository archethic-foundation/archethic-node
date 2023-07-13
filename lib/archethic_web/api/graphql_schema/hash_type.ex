defmodule ArchethicWeb.API.GraphQLSchema.HashType do
  @moduledoc false

  use Absinthe.Schema.Notation
  alias Archethic.Crypto

  @desc """
  The [Hash] scalar type represents a cryptographic hash used in
  the Archethic network with an identification byte to specify from which algorithm the hash was generated.
  The Hash appears in a JSON response as Base16 formatted string. The parsed hash will
  be converted to a binary and any invalid hash with an invalid algorithm or invalid size will be rejected
  """
  scalar :hash do
    serialize(&Base.encode16/1)
    parse(&parse_hash/1)
  end

  @spec parse_hash(Absinthe.Blueprint.Input.String.t()) :: {:ok, binary()} | :error
  defp parse_hash(%Absinthe.Blueprint.Input.String{value: hash}) do
    with {:ok, hash} <- Base.decode16(hash, case: :mixed),
         true <- Crypto.valid_hash?(hash) do
      {:ok, hash}
    else
      _ ->
        :error
    end
  end

  defp parse_hash(_), do: :error
end
