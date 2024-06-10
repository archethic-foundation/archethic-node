defmodule Archethic.Contracts.Contract.State do
  @moduledoc """
  Module to manipulate the contract state
  """
  alias Archethic.Utils.TypedEncoding

  @max_compressed_state_size 256 * 1024

  @type t() :: map()
  @type encoded() :: binary()

  @spec empty() :: t()
  def empty(), do: %{}

  @spec empty?(state :: t()) :: boolean()
  def empty?(state), do: state == empty()

  @spec valid_size?(encoded_state :: encoded()) :: boolean()
  def valid_size?(encoded_state), do: byte_size(encoded_state) <= @max_compressed_state_size

  @doc """
  Serialize the given state
  """
  @spec serialize(t()) :: encoded()
  def serialize(state), do: TypedEncoding.serialize(state, :compact)

  @doc """
  Deserialize the state
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(bitsting), do: TypedEncoding.deserialize(bitsting, :compact)

  @doc """
  Return a valid JSON of the given state
  Handles the fact that keys can be non-string
  """
  @spec to_json(state :: t()) :: map()
  def to_json(state) do
    serialize_map_keys(state)
  end

  @doc """
  Returns the state as a prettified JSON
  Handles the fact that keys can be non-string
  """
  @spec format(state :: t()) :: String.t()
  def format(state) do
    Jason.encode!(to_json(state), pretty: true)
  end

  defp serialize_map_keys(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn
      {k, v}, acc when is_binary(k) ->
        Map.put(acc, k, serialize_map_keys(v))

      {k, v}, acc ->
        Map.put(acc, Jason.encode!(k), serialize_map_keys(v))
    end)
  end

  defp serialize_map_keys(list) when is_list(list) do
    Enum.map(list, &serialize_map_keys/1)
  end

  defp serialize_map_keys(term), do: term
end
