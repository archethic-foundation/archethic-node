defmodule ArchethicWeb.API.GraphQL.Schema.IntegerType do
  @moduledoc false

  use Absinthe.Schema.Notation

  @desc """
  The [Positive Integer] scalar type represents a positive number
  """
  scalar :pos_integer do
    parse(&do_parse_pos_integer/1)
  end

  @desc """
  The [Non Negative Integer] scalar type represents a non negative number
  """
  scalar :non_neg_integer do
    parse(&do_parse_non_neg_integer/1)
  end

  defp do_parse_pos_integer(%Absinthe.Blueprint.Input.Integer{value: integer})
       when integer >= 1 do
    {:ok, integer}
  end

  defp do_parse_pos_integer(_) do
    :error
  end

  defp do_parse_non_neg_integer(%Absinthe.Blueprint.Input.Integer{value: integer})
       when integer >= 0 do
    {:ok, integer}
  end

  defp do_parse_non_neg_integer(_) do
    :error
  end
end
