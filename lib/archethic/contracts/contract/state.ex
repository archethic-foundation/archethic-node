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
end
