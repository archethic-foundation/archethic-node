defmodule Archethic.P2P.Message.Ping do
  @moduledoc """
  Represents a message using to test node availability
  """

  defstruct []

  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Ok

  @type t :: %__MODULE__{}

  @spec process(__MODULE__.t(), Message.metadata()) :: Ok.t()
  def process(%__MODULE__{}, _), do: %Ok{}

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{}), do: <<>>

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::binary>>), do: {%__MODULE__{}, rest}
end
