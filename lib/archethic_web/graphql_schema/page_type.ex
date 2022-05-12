defmodule ArchethicWeb.GraphQLSchema.PageType do
  @moduledoc false

  use Absinthe.Schema.Notation

  @desc """
  The [Page] scalar type represents the page number
  """
  scalar :page do
    parse(&do_parse/1)
  end

  @spec do_parse(Absinthe.Blueprint.Input.Integer.t()) ::
          {:ok, integer()} | :error
  defp do_parse(%Absinthe.Blueprint.Input.Integer{value: page_value}) when page_value >= 1 do
    {:ok, page_value}
  end

  defp do_parse(_page) do
    :error
  end
end
