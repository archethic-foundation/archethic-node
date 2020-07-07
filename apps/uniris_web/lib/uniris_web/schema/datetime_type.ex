defmodule UnirisWeb.Schema.DateTimeType do
  @moduledoc false

  use Absinthe.Schema.Notation

  @desc """
  The [Timestamp] scalar type represents a UNIX timestamp in seconds
  """
  scalar :timestamp do
    serialize(&DateTime.to_unix/1)
    parse(&parse_timestamp/1)
  end

  @spec parse_timestamp(Absinthe.Blueprint.Input.Integer.t()) :: {:ok, DateTime.t()} | :error
  defp parse_timestamp(%Absinthe.Blueprint.Input.Integer{value: timestamp}) do
    timestamp
    |> DateTime.from_unix(:millisecond)
    |> case do
      {:ok, date} ->
        {:ok, date}

      _ ->
        :error
    end
  end

  defp parse_timestamp(_), do: :error
end
