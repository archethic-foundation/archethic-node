defmodule Archethic.P2P.Message.Ok do
  @moduledoc """
  Represents an OK message
  """
  defstruct []

  @type t :: %__MODULE__{}

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{}), do: <<>>

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>), do: {%__MODULE__{}, rest}
end
