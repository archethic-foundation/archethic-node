defmodule Archethic.P2P.Message.Ok do
  @moduledoc """
  Represents an OK message
  """
  defstruct []

  @type t :: %__MODULE__{}

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{}) do
    <<254::8>>
  end
end
