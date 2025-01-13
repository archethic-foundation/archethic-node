defmodule Archethic.Contracts.Contract.State do
  @moduledoc """
  Module to manipulate the contract state
  """
  alias Archethic.Utils.TypedEncoding
  alias Archethic.Utils
  alias Archethic.Utils.VarInt
  alias Archethic.Mining

  # 3 MB
  @max_compressed_state_size 3 * 1024 * 1024

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
  @spec serialize(t(), protocol_version :: pos_integer()) :: encoded()
  def serialize(state, protocol_version \\ Mining.protocol_version())

  def serialize(state, protocol_version) when protocol_version < 9,
    do: TypedEncoding.serialize(state, :compact)

  def serialize(state, _protocol_version) do
    encoded_payload =
      TypedEncoding.serialize(state, :compact)
      |> Utils.wrap_binary()
      |> :zlib.zip()

    encoded_payload_size = encoded_payload |> byte_size() |> VarInt.from_value()

    <<encoded_payload_size::binary, encoded_payload::binary>>
  end

  @doc """
  Deserialize the state
  """
  @spec deserialize(bitstring(), protocol_version :: pos_integer()) :: {t(), bitstring()}
  def deserialize(bitstring, protocol_version) when protocol_version < 9,
    do: TypedEncoding.deserialize(bitstring, :compact)

  def deserialize(bitstring, _protocol_version) do
    {encoded_payload_size, rest} = VarInt.get_value(bitstring)

    <<encoded_payload::binary-size(encoded_payload_size), rest::bitstring>> = rest

    {state, _} = :zlib.unzip(encoded_payload) |> TypedEncoding.deserialize(:compact)

    {state, rest}
  end

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
