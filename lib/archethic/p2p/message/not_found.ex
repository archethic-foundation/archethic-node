defmodule Archethic.P2P.Message.NotFound do
  @moduledoc """
  Represents a message when the transaction is not found
  """
  defstruct []

  @type t :: %__MODULE__{}

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{}) do
    <<253::8>>
  end
end
