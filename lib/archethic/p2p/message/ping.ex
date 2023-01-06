defmodule Archethic.P2P.Message.Ping do
  @moduledoc """
  Represents a message using to test node availability
  """

  defstruct []

  alias Archethic.Crypto
  alias Archethic.P2P.Message.Ok

  @type t :: %__MODULE__{}

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{}, _), do: %Ok{}
end
