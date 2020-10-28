defmodule Uniris.DB.CassandraImpl.CQL do
  @moduledoc false

  @spec list_to_cql(list()) :: binary()
  def list_to_cql(_fields, acc \\ [], prepend \\ "")

  def list_to_cql([{k, v} | rest], acc, prepend = "") do
    list_to_cql(rest, ["#{list_to_cql(v, [], k)}" | acc], prepend)
  end

  def list_to_cql([{k, v} | rest], acc, prepend) do
    nested_prepend = "#{prepend}.#{k}"
    list_to_cql(rest, ["#{list_to_cql(v, [], nested_prepend)}" | acc], prepend)
  end

  def list_to_cql([key | rest], acc, prepend = "") do
    list_to_cql(rest, [key | acc], prepend)
  end

  def list_to_cql([key | rest], acc, prepend) do
    list_to_cql(rest, ["#{prepend}.#{key}" | acc], prepend)
  end

  def list_to_cql([], [], _), do: "*"

  def list_to_cql([], acc, _prepend) do
    acc
    |> Enum.reverse()
    |> Enum.join(",")
  end
end
