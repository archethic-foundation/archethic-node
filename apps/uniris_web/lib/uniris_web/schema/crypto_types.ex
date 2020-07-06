defmodule UnirisWeb.Schema.CryptoTypes do
  @moduledoc false

  use Absinthe.Schema.Notation

  @desc """
  The [Hash] scalar type represents a cryptographic hash used in
  the Uniris network with an identification byte to specify from which algorithm the hash was generated.
  The Hash appears in a JSON response as Base16 formatted string. The parsed hash will
  be converted to a binary and any invalid hash with an invalid algorithm or invalid size will be rejected
  """
  scalar :hash do
    serialize(&Base.encode16/1)
    parse(&parse_hash/1)
  end

  @desc """
  The [PublicKey] scalar type represents a cryptographic public key used in
  the Uniris network with an identification byte to specify from which curve the key was generated.
  The PublicKey appears in a JSON response as Base16 formatted string. The parsed public key will
  be converted to a binary and any invalid public key with an invalid curve or invalid size will be rejected
  """
  scalar :public_key do
    serialize(&Base.encode16/1)
    parse(&parse_public_key/1)
  end

  @spec parse_hash(Absinthe.Blueprint.Input.String.t()) :: {:ok, binary()} | :error
  defp parse_hash(%Absinthe.Blueprint.Input.String{value: hash}) do
    with {:ok, hash = <<hash_id::8, rest::binary>>} <- Base.decode16(hash, case: :mixed),
         true <- UnirisCore.Crypto.hash_size(hash_id) == byte_size(rest) do
      {:ok, hash}
    else
      _ ->
        :error
    end
  end

  defp parse_hash(_), do: :error

  @spec parse_public_key(Absinthe.Blueprint.Input.String.t()) :: {:ok, binary()} | :error
  defp parse_public_key(%Absinthe.Blueprint.Input.String{value: key}) do
    with {:ok, key = <<curve_id::8, rest::binary>>} <- Base.decode16(key, case: :mixed),
         true <- UnirisCore.Crypto.key_size(curve_id) == byte_size(rest) do
      {:ok, key}
    else
      _ ->
        :error
    end
  end

  defp parse_public_key(_), do: :error
end
