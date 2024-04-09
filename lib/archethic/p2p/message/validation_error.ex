defmodule Archethic.P2P.Message.ValidationError do
  @moduledoc """
  Represents an error message
  """
  alias ArchethicWeb.TransactionSubscriber
  alias Archethic.Crypto
  alias Archethic.Mining.Error
  alias Archethic.P2P.Message.Ok
  alias Archethic.Utils

  defstruct [:error, :address]

  @type t :: %__MODULE__{
          error: Error.t(),
          address: Crypto.prepended_hash()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{error: error, address: address}, _) do
    TransactionSubscriber.report_error(address, error)
    %Ok{}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{error: error, address: address}) do
    <<address::binary, Error.serialize(error)::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {error, rest} = Error.deserialize(rest)

    {%__MODULE__{error: error, address: address}, rest}
  end
end
