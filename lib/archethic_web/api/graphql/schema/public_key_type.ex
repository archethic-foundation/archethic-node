defmodule ArchethicWeb.API.GraphQL.Schema.PublicKeyType do
  @moduledoc false

  use Absinthe.Schema.Notation
  alias Archethic.Crypto

  @desc """
  The [PublicKey] scalar type represents a public key.
  The PublicKey appears in a JSON response as Base16 formatted string. The parsed public key will
  be converted to a binary and any invalid address with an invalid algorithm or invalid size will be rejected
  """
  scalar :public_key do
    serialize(&Base.encode16/1)
    parse(&parse_public_key/1)
  end

  @spec parse_public_key(Absinthe.Blueprint.Input.String.t()) :: {:ok, binary()} | :error
  defp parse_public_key(%Absinthe.Blueprint.Input.String{value: public_key}) do
    with {:ok, pub} <- Base.decode16(public_key, case: :mixed),
         true <- Crypto.valid_public_key?(pub) do
      {:ok, pub}
    else
      _ ->
        :error
    end
  end

  defp parse_public_key(_), do: :error
end
