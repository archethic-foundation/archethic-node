defmodule UnirisWeb.Schema.HexType do
  @moduledoc false

  use Absinthe.Schema.Notation

  @desc """
  The [Hex] scalar type represents an hexadecimal
  """
  scalar :hex do
    serialize(&Base.encode16/1)
    parse(&parse_hex/1)
  end

  @spec parse_hex(Absinthe.Blueprint.Input.String.t()) :: {:ok, binary()} | :error
  defp parse_hex(%Absinthe.Blueprint.Input.String{value: hex}) do
    Base.decode16(hex, case: :mixed)
  end

  defp parse_hex(_), do: :error
end
