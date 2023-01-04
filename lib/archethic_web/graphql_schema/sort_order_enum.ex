defmodule ArchethicWeb.GraphQLSchema.SortOrderEnum do
  @moduledoc false

  use Absinthe.Schema.Notation

  @desc """
  SortOrder represents the order of the result
  possible values are :asc or :desc
  """
  enum :sort_order do
    value(:asc, description: "Ascending order")
    value(:desc, description: "Descending order")
  end
end
