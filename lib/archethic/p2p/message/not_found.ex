defmodule Archethic.P2P.Message.NotFound do
  @moduledoc """
  Represents a message when the transaction is not found
  """
  defstruct []

  @type t :: %__MODULE__{}

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{}), do: <<>>

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>), do: {%__MODULE__{}, rest}
end
