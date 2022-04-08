defmodule ArchEthic.P2P.Message.Ok do
  @moduledoc """
  Represents an OK message
  """
  defstruct []

  @type t :: %__MODULE__{}

  use ArchEthic.P2P.Message, message_id: 254

  def encode(%__MODULE__{}) do
    <<>>
  end

  def decode(rest) when is_bitstring(rest) do
    {%__MODULE__{}, rest}
  end

  def process(%__MODULE__{}) do
  end
end
