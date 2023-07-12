defmodule ArchethicWeb.GraphQLSchema.DateTimeType do
  @moduledoc false

  use Absinthe.Schema.Notation

  @desc """
  The [Timestamp] scalar type represents a UNIX timestamp in seconds
  """
  scalar :timestamp do
    serialize(&DateTime.to_unix/1)
    parse(&parse_datetime/1)
  end

  defp parse_datetime(%Absinthe.Blueprint.Input.String{value: value}) do
    with {timestamp, ""} <- Integer.parse(value),
         {:ok, datetime} <- DateTime.from_unix(timestamp) do
      {:ok, datetime}
    else
      _ ->
        :error
    end
  end

  defp parse_datetime(%Absinthe.Blueprint.Input.Integer{value: value}) do
    DateTime.from_unix(value)
  end

  defp parse_datetime(_), do: :error
end
