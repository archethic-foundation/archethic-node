defmodule Archethic.Utils.Data.Mutate do
  @moduledoc """
  Utilities for assisting with data mutation.
  ex: from_map , to _map
  """

  @doc """
  Converts a list of map to a Single Map.

  ## Examples

      iex> [%{k: 5}, %{m: 5}, %{v: 3}]
      ...> |>Mutate.list_of_map_to_map()
      %{k: 5, m: 5, v: 3}

  """
  def list_of_map_to_map(list_of_map) do
    Enum.reduce(list_of_map, _acc = %{}, fn a, acc ->
      Map.merge(a, acc, fn _key, a1, a2 ->
        a1 + a2
      end)
    end)
  end
end
