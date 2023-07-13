defmodule ArchethicWeb.API.GraphQLSchema.AddressType do
  @moduledoc false

  use Absinthe.Schema.Notation
  alias Archethic.Crypto

  @desc """
  The [Address] scalar type represents a transaction's address.
  The Address appears in a JSON response as Base16 formatted string. The parsed address will
  be converted to a binary and any invalid address with an invalid algorithm or invalid size will be rejected
  """
  scalar :address do
    serialize(&Base.encode16/1)
    parse(&parse_address/1)
  end

  @spec parse_address(Absinthe.Blueprint.Input.String.t()) :: {:ok, binary()} | :error
  defp parse_address(%Absinthe.Blueprint.Input.String{value: address}) do
    with true <- String.length(address) > 0,
         {:ok, addr} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(addr) do
      {:ok, addr}
    else
      _ ->
        :error
    end
  end

  defp parse_address(_), do: :error
end
