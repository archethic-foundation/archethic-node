defmodule Archethic.P2P.Message.ValidationError do
  @moduledoc """
  Represents an error message
  """
  alias ArchethicWeb.TransactionSubscriber
  alias Archethic.Crypto
  alias Archethic.P2P.Message.Ok
  alias Archethic.Utils.VarInt

  defstruct [:context, :reason, :address]

  @type t :: %__MODULE__{
          context: :invalid_transaction | :network_issue,
          reason: binary(),
          address: binary()
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{context: :network_issue, reason: reason, address: address}) do
    <<234::8, address::binary, reason |> byte_size() |> VarInt.from_value()::binary,
      reason::binary, 0::8>>
  end

  def encode(%__MODULE__{context: :invalid_transaction, reason: reason, address: address}) do
    <<234::8, address::binary, reason |> byte_size() |> VarInt.from_value()::binary,
      reason::binary, 1::8>>
  end

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{context: context, reason: reason, address: address}, _) do
    TransactionSubscriber.report_error(address, context, reason)
    %Ok{}
  end
end
