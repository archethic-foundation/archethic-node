defmodule ArchEthicWeb.GraphQLSchema.HexType do
  @moduledoc false

  use Absinthe.Schema.Notation

  @desc """
  The [Hex] scalar type represents an hexadecimal
  """
  scalar :hex do
    serialize(&Base.encode16/1)
    parse(&Base.decode16(&1, case: :mixed))
  end
end
