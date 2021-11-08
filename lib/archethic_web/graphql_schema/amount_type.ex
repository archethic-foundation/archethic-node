defmodule ArchEthicWeb.GraphQLSchema.AmountType do
  @moduledoc false

  use Absinthe.Schema.Notation

  @unit_uco 100_000_000

  @desc """
  The [Amount] scalar type represents an amount
  """
  scalar :amount do
    serialize(&do_serialize/1)
    parse(&do_parse/1)
  end

  defp do_serialize(amount) do
    amount / @unit_uco
  end

  defp do_parse(amount) do
    {:ok, amount * @unit_uco}
  end
end
