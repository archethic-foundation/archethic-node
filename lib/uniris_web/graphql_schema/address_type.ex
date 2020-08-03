defmodule UnirisWeb.GraphQLSchema.AddressType do
  @moduledoc false

  use Absinthe.Schema.Notation
  alias Uniris.Crypto

  @desc """
  The [Address] scalar type represents a cryptographic hash used in
  the Uniris network with an identification byte to specify from which algorithm the hash was generated.
  The Hash appears in a JSON response as Base16 formatted string. The parsed hash will
  be converted to a binary and any invalid hash with an invalid algorithm or invalid size will be rejected
  """
  scalar :address do
    serialize(&Base.encode16/1)
    parse(&parse_address/1)
  end

  @spec parse_address(Absinthe.Blueprint.Input.String.t()) :: {:ok, binary()} | :error
  defp parse_address(%Absinthe.Blueprint.Input.String{value: hash}) do
    with {:ok, hash = <<hash_id::8, rest::binary>>} <- Base.decode16(hash, case: :mixed),
         true <- Crypto.hash_size(hash_id) == byte_size(rest) do
      {:ok, hash}
    else
      _ ->
        :error
    end
  end

  defp parse_address(_), do: :error
end
